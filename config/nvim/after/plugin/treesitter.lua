-- cargo install tree-sitter-cli
if not pcall(require, "nvim-treesitter.configs") then return end
local ts_setup = {
	ensure_installed = {
		"dockerfile",
		"go",
		"html",
		"javascript",
		"java",
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

	-- see p00f/nvim-ts-rainbow
	rainbow = {
		enable = true,
		-- disable = { "jsx", "cpp" }, list of languages you want to disable the plugin for
		extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
		max_file_lines = nil, -- Do not enable for files with more than n lines, int
		-- colors = {}, -- table of hex strings
		-- termcolors = {} -- table of colour name strings
	},

	-- Indentation based on treesitter for the = operator.
	-- NOTE: This is an experimental feature.
	indent = {
		enable = true
	}
}

require("nvim-treesitter.configs").setup(ts_setup)

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
	mode = 'cursor', -- Line used to calculate context. Choices: 'cursor', 'topline'
})
