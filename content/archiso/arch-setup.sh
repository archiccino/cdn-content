#!/bin/bash

pacman -Sy neovim zsh networkmanager git github-cli glab ntfs-3g --noconfirm
pacman -S amd-ucode --noconfirm

echo "en_IN UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_IN.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc --utc

systemctl enable NetworkManager
systemctl enable fstrim.timer

echo "[multilib]" >> /etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
pacman -Sy

# Set the root password in a loop until successful
while true; do
    echo "Set the root password:"
    if passwd; then
        echo "Root password set successfully."
        break
    else
        echo "Error: Failed to set the root password. Try again."
    fi
done

# Loop for entering a valid username
while true; do
    read -p "Enter the new username: " username

    # Validate the username
    if [[ -z "$username" || ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: Invalid username. Usernames must start with a letter or underscore and can contain letters, digits, dashes, and underscores."
        continue
    fi

    # Check if the user already exists
    if id -u "$username" >/dev/null 2>&1; then
        echo "Error: User '$username' already exists. Try again."
        continue
    fi

    # If valid, break the loop
    break
done

# Create the user with necessary groups and Zsh as the default shell
while true; do
    if useradd -m -g users -G wheel,storage,power -s /bin/zsh "$username"; then
        echo "User '$username' created successfully."
        break
    else
        echo "Error: Failed to create the user '$username'. Try again."
        read -p "Do you want to retry? (y/n): " retry
        if [[ "$retry" != "y" ]]; then
            echo "Aborting user creation."
            break
        fi
    fi
done

# Set the password for the new user in a loop
while true; do
    echo "Set the password for '$username':"
    if passwd "$username"; then
        echo "Password for '$username' set successfully."
        break
    else
        echo "Error: Failed to set the password for '$username'. Try again."
    fi
done

# Check if `sudo` is installed and grant wheel group sudo access
if command -v sudo >/dev/null 2>&1; then
    echo "Granting sudo access to the 'wheel' group..."
    if ! grep -q "^%wheel" /etc/sudoers; then
        echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
        echo "Sudo access granted to the 'wheel' group."
    else
        echo "Sudo access for the 'wheel' group is already configured."
    fi
else
    echo "Warning: 'sudo' is not installed. Install it manually to enable sudo access."
fi

echo "User setup completed successfully."

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults rootpw" >> /etc/sudoers
echo "Defaults !tty_tickets" >> /etc/sudoers

# Prompt for bootloader choice
read -p "Choose bootloader (grub or direct boot) or skip bootloader setup entirely? 
(grub is better for dual boot) [g/d/n]: " boot

# Validate user input
case $boot in
    g)  # GRUB setup
        echo "Installing GRUB bootloader..."
        bootctl --path=/boot install || { echo "Error: Failed to install bootctl."; exit 1; }
        pacman -S grub efibootmgr os-prober --noconfirm || { echo "Error: Failed to install GRUB dependencies."; exit 1; }
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || { echo "Error: GRUB installation failed."; exit 1; }
        grub-mkconfig -o /boot/grub/grub.cfg || { echo "Error: Failed to generate GRUB configuration."; exit 1; }
        echo "GRUB setup completed successfully."
        ;;
    
    n)  # Skip bootloader setup
        echo "Skipping bootloader setup as per your choice."
        ;;

    d)  # Direct boot setup
        echo "Setting up system for direct boot..."
        bootctl --path=/boot install || { echo "Error: Failed to install bootctl."; exit 1; }
        mkdir -p /boot/loader/entries || { echo "Error: Failed to create loader entries directory."; exit 1; }
        
        # Create the loader entry for Arch Linux
        entry_path="/boot/loader/entries/arch.conf"
        echo "title ArchLinux" > $entry_path
        echo "linux /vmlinuz-linux" >> $entry_path
        echo "initrd /initramfs-linux.img" >> $entry_path
        
        # Prompt for the root partition and validate input
        lsblk
        read -p "Enter the root partition name (e.g., sda1, nvme0n1p2): " partname
        if [ -z "$partname" ] || ! blkid /dev/"$partname" > /dev/null 2>&1; then
            echo "Error: Invalid or non-existent partition name entered."
            exit 1
        fi

        # Add the PARTUUID of the root partition to the loader entry
        partuuid=$(blkid -s PARTUUID -o value /dev/$partname)
        if [ -z "$partuuid" ]; then
            echo "Error: Failed to retrieve PARTUUID for /dev/$partname."
            exit 1
        fi
        echo "options root=PARTUUID=$partuuid rw" >> $entry_path
        echo "Direct boot setup completed successfully."
        ;;
    
    *)  # Invalid choice
        echo "Error: Invalid choice. Please run the script again and select 'g', 'd', or 'n'."
        exit 1
        ;;
esac

echo "KEYMAP=us" > /etc/vconsole.conf
echo "arch" > /etc/hostname

pacman -S plasma cosmic firefox dolphin


cd /home/$username
git clone https://aur.archlinux.org/yay.git
cd yay
