-- :help telescope.builtin

if not pcall(require, "telescope") then return end

local telescope = require("telescope")

local setup = {
	defaults = {
		wrap_results = true,
	},

	pickers = {
		find_files = {
			-- theme = "dropdown",
		}
	},
}

-- if pcall(require, "telescope.config") then
-- local telescopeConfig = require("telescope.config")
-- local vimgrep_arguments = { unpack(telescopeConfig.values.vimgrep_arguments) }
-- local vimgrep_arguments = {
-- "rg",
-- -- "--column",
-- -- "--hidden",
-- -- "--line-number",
-- "--no-heading",
-- -- "--smart-case",
-- "--with-filename"
-- }
-- require("tm.functions").print_table(vimgrep_arguments)
-- setup.pickers.find_files.find_command = vimgrep_arguments
-- end

telescope.setup(setup)

local tb = require("telescope.builtin")

vim.keymap.set("n", "<C-P>", tb.find_files, { silent = true })
vim.keymap.set("n", "<S-R>", tb.live_grep, { silent = true })
vim.keymap.set("n", "<C-D>", tb.diagnostics, { silent = true })
