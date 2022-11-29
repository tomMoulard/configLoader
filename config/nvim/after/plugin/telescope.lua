-- :help telescope.builtin

if not pcall(require, "telescope") then return end

local telescope = require("telescope")

telescope.setup{
	defaults = {
		wrap_results = true,
	},

	pickers = {
		find_files = {
			theme = "dropdown",
		}
	},
}

local tb = require("telescope.builtin")

vim.keymap.set("n", "<C-P>", tb.find_files, {silent=true})
vim.keymap.set("n", "<S-R>", tb.live_grep, {silent=true})
vim.keymap.set("n", "<C-D>", tb.diagnostics, {silent=true})
