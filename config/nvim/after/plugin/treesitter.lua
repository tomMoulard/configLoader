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

if not pcall(require, "treesitter-context") then return end

require("treesitter-context").setup({
	enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
	max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
	trim_scope = 'outer', -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
	patterns = { -- Match patterns for TS nodes. These get wrapped to match at word boundaries.
		-- For all filetypes
		-- Note that setting an entry here replaces all other patterns for this entry.
		-- By setting the 'default' entry below, you can control which nodes you want to
		-- appear in the context window.
		default = {
			'class',
			'function',
			'method',
			'for', -- These won't appear in the context
			'while',
			'if',
			'switch',
			'case',
		},
		-- Example for a specific filetype.
		-- If a pattern is missing, *open a PR* so everyone can benefit.
		--   rust = {
		--       'impl_item',
		--   },
	},
	exact_patterns = {
		-- Example for a specific filetype with Lua patterns
		-- Treat patterns.rust as a Lua pattern (i.e "^impl_item$" will
		-- exactly match "impl_item" only)
		-- rust = true,
	},

	-- [!] The options below are exposed but shouldn't require your attention,
	--     you can safely ignore them.

	zindex = 20, -- The Z-index of the context window
	mode = 'cursor',  -- Line used to calculate context. Choices: 'cursor', 'topline'
})
