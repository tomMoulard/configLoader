vim.g.NERDTreeShowHidden = 1
vim.g.NERDTreeIgnore = {
	".*.swp",
	"*.o",
	"*.out",
	"*.pyc",
}

vim.keymap.set("n", "<F1>", ":NERDTreeToggle<CR>", {silent=true})
