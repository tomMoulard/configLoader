if not pcall(require, "nvim-treesitter.configs") then return end

require("nvim-treesitter.configs").setup {
	ensure_installed = {
		"dockerfile",
		"go",
		"html",
		"javascript",
		"json",
		"latex",
		"lua",
		"make",
		"markdown",
		"markdown_inline",
		"rust",
		"scss",
		"toml",
		"vim",
		"yaml",
	},

	-- Automatically install missing parsers when entering buffer
	auto_install = true,

	highlight = {
		-- `false` will disable the whole extension
		enable = true,
	},

	-- Indentation based on treesitter for the = operator.
	-- NOTE: This is an experimental feature.
	indent = {
		enable = true
	}
}

vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
