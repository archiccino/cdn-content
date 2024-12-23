document.addEventListener("DOMContentLoaded", async function () {
	let script_list = await fetch("/scripts.jsonc").then((response) =>
		response.json()
	)

	script_list = Array.from(script_list).map((item) => {
		return getScriptItem(item)
	})

	script_list = script_list.join("")

	document.querySelector("#dynamic").innerHTML = script_list

	document.querySelectorAll(".btn-copy").forEach((btn) => {
		btn.addEventListener("click", (e) => {
			const path = e.target.getAttribute("data-path")
			navigator.clipboard
				.writeText(`https://cdn.archiccinolinux.xyz/content/${path}`)
				.then(() => {
					alert("Copied to clipboard")
				})
		})
	})
})

function getScriptItem(item) {
	return `
		<li class="script-item">
			<div class="name">name: ${item.name}</div>
			<div class="description">desc: ${item.description}</div>
			<div class="version">v${item.version}</div>
			<div class="author">author: ${item.author.name}</div>
			<div class="author">contact: ${item.author.email}</div>
			<div class="dependencies">dependencies: ${item.dependencies.join(", ")}</div>
			<div class="tags">tags: ${item.tags.join(", ")}</div>
			<button class="btn-copy" data-path="${item.path}" >Copy URI</button>
		</li>
	`
}
