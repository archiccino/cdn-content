#!/bin/bash

set -e  # Exit immediately if a command fails
set -u  # Treat unset variables as an error
set -o pipefail  # Prevent errors in a pipeline from being masked

### Function to check for existing EFI partitions ###
check_efi_partition() {
    echo "Scanning for existing EFI System Partitions (EF00)..."
    lsblk -o NAME,PARTTYPE,MOUNTPOINT | grep 'ef00' || return 1
}

### Function to prompt user for partition if EFI is missing ###
get_partition_for_efi() {
    echo "No EFI partition found!"
    lsbllk -o NAME,PARTTYPE,MOUNTPOINT
    read -rp "Enter the partition to shrink by 1GiB for EFI (e.g., nvme0n1p3, sda2): " partition
    if [[ -z "$partition" ]]; then
        echo "No partition provided. Exiting..."
        exit 1
    fi

    # Resize the partition (assuming GPT and 1GiB shrinkage)
    echo "Shrinking $partition by 1GiB..."
    parted "/dev/${partition%[0-9]*}" resizepart "${partition##*[a-z]}" -1GiB || {
        echo "Partition resizing failed! Exiting..."
        exit 1
    }

    # Create the EFI partition
    new_efi_part="${partition%[0-9]*}p$(($(lsblk -rno MAJ:MIN | wc -l) + 1))"
    echo "Creating new EFI partition at $new_efi_part..."
    parted "/dev/${partition%[0-9]*}" mkpart ESP fat32 -1GiB 100% || {
        echo "EFI partition creation failed! Exiting..."
        exit 1
    }
    parted "/dev/${partition%[0-9]*}" set $(lsblk -rno NAME | grep -E "^${new_efi_part##*/}") esp on
}

### Function to check if partition is Btrfs ###
check_btrfs_partition() {
    local part=$1
    local fstype
    fstype=$(lsblk -no FSTYPE "/dev/$part" | tr -d ' ')

    if [[ "$fstype" != "btrfs" ]]; then
        echo "Warning: Partition $part is not formatted as Btrfs."
        read -rp "Do you want to proceed and format it as Btrfs? (P/Proceed, E/Exit) " choice
        case "$choice" in
            [Pp]*) echo "Formatting $part as Btrfs..."; mkfs.btrfs -f "/dev/$part" ;;
            *) echo "Exiting..."; exit 1 ;;
        esac
    fi
}

### Function to create Btrfs subvolumes ###
create_btrfs_subvolumes() {
    local part=$1

    echo "Mounting $part to /mnt..."
    mount "/dev/$part" /mnt

    echo "Creating Btrfs subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@desktop
    btrfs subvolume create /mnt/@user_config
    btrfs subvolume create /mnt/@snapshots

    echo "Unmounting temporary mount..."
    umount /mnt
}

### Function to mount Btrfs subvolumes ###
mount_btrfs_subvolumes() {
    local part=$1

    echo "Mounting Btrfs subvolumes..."
    mount -o subvol=@ "/dev/$part" /mnt

    mkdir -p /mnt/{boot,home,.snapshots,.btrfsroot}
    mount -o subvol=@home "/dev/$part" /mnt/home
    mount -o subvol=@snapshots "/dev/$part" /mnt/.snapshots
    mount -o subvolid=5 "/dev/$part" /mnt/.btrfsroot  # Root volume
}

### Function to create user directories ###
setup_home_dirs() {
    echo "Creating user directories..."
    mkdir -p /mnt/home/.desktop
    mkdir -p /mnt/home/.user_config
}

### Main Execution ###

# Step 1: Check for EFI partition
if ! check_efi_partition; then
    get_partition_for_efi
fi

# Step 2: Ask user for the Btrfs partition
read -rp "Enter the partition to format as Btrfs (e.g., nvme0n1p3, sda2): " btrfs_part
if [[ -z "$btrfs_part" ]]; then
    echo "No partition provided. Exiting..."
    exit 1
fi

# Step 3: Validate or format Btrfs
check_btrfs_partition "$btrfs_part"

# Step 4: Create Btrfs subvolumes
create_btrfs_subvolumes "$btrfs_part"

# Step 5: Mount subvolumes
mount_btrfs_subvolumes "$btrfs_part"

# Step 6: Setup home directories
setup_home_dirs

echo "Partitioning complete!"
