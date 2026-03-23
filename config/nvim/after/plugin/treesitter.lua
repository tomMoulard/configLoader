-- cargo install tree-sitter-cli
if not pcall(require, "nvim-treesitter") then return end

require("nvim-treesitter").setup({
    install_dir = vim.fn.stdpath('data') .. '/site',
})
-- Install parsers (async, no-op if already installed)
require("nvim-treesitter").install({
    "dockerfile", "go", "html", "javascript", "java",
    "json", "latex", "lua", "make", "markdown",
    "markdown_inline", "rust", "scss", "toml", "vim", "yaml",
})

-- Enable treesitter-based syntax highlighting for every buffer.
-- The new nvim-treesitter API no longer has a "highlight" module; highlighting
-- is now done via the built-in vim.treesitter API. Telescope's preview does
-- this automatically, which is why it showed more colours than the editor.
vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
        pcall(vim.treesitter.start, args.buf)
    end,
})

vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

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
