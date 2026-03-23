local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.notify("Installing lazy.nvim: " .. lazypath, vim.log.levels.INFO)
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

if not pcall(require, "lazy") then
	vim.notify("Lazy.nvim failed to load, skipping", vim.log.levels.ERROR)
	return
end

local plugins = {
	{ -- color scheme.
		"tanvirtin/monokai.nvim",
		lazy = false,
		priority = 1000, -- load colorscheme before other plugins.
	},

	{ "tpope/vim-fugitive" },

	{ -- find files or content.
		"nvim-telescope/telescope.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim", -- grep
		}
	},

	{ -- parser generator tool and an incremental parsing library.
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		lazy = false,
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
			"nvim-treesitter/nvim-treesitter-context",
		},
	},

	{ -- shows git status.
		"lewis6991/gitsigns.nvim",
		cond = function()
			-- do not load plugin if folder does not contain a .git folder.
			return vim.fn.finddir(".git", ".;") ~= ""
		end,
	},

	{ -- autocomplete
		"hrsh7th/nvim-cmp",
		lazy = false,
		dependencies = {
			"folke/lazydev.nvim",                   -- docs and completion for the nvim lua API.
			"hrsh7th/cmp-buffer",                   -- autocomplete strings in buffer.
			"hrsh7th/cmp-cmdline",                  -- nvim-cmp source for vim's cmdline.
			"hrsh7th/cmp-nvim-lsp",                 -- nvim-cmp source for neovim's built-in language server client.
			"hrsh7th/cmp-nvim-lsp-signature-help",  -- nvim-cmp source for displaying function signatures with the current parameter emphasized.
			"hrsh7th/cmp-nvim-lua",                 -- nvim-cmp source for neovim Lua API.
			"hrsh7th/cmp-path",                     -- autocomplete file paths.
			"ray-x/cmp-treesitter",                 -- nvim-cmp source for treesitter nodes.
		},
	},

	{
		"folke/lazydev.nvim",
		ft = "lua", -- only load on lua files
		opts = {
			library = {
				-- See the configuration section for more details
				-- Load luvit types when the `vim.uv` word is found
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},

	{
		"fatih/vim-go",
		build = ":GoUpdateBinaries",
		ft = { "go", "gohtmltmpl" }, -- lazy load on go filetype.
	},

	{
		"glacambre/firenvim",
		-- Lazy load firenvim
		-- Explanation: https://github.com/folke/lazy.nvim/discussions/463#discussioncomment-4819297
		cond = not not vim.g.started_by_firenvim,
		build = function()
			require("lazy").load({ plugins = "firenvim", wait = true })
			vim.fn["firenvim#install"](0)
		end
	},

	-- Debug Adapter Protocol
	{
		"mfussenegger/nvim-dap",
		enabled = false, -- disable until working.
		ft = { "go" }, -- lazy load on filetypes.
		keys = {
		},
		dependencies = {
			"theHamsta/nvim-dap-virtual-text",
			{
				"rcarriga/nvim-dap-ui", -- UI for DAP.
				ft = { "go" },      -- lazy load on filetypes.
				keys = {
					{ "<F9>", function() require('dapui').toggle() end, mode = "n", desc = "Toggle DAP UI", silent = true },
				},
			},
		},
	},
	{                -- Go Delve debugger.
		"leoluz/nvim-dap-go",
		enabled = false, -- disable until working.
		ft = { "go" }, -- lazy load on filetypes.
	},
	{
		"rcarriga/nvim-dap-ui", -- UI for DAP.
		enabled = false,      -- disable until working.
		ft = { "go" },        -- lazy load on filetypes.
		dependencies = { "mfussenegger/nvim-dap" }
	},

	-- match pairs ( '"[{}]"' ), see :h insx
	{ "hrsh7th/nvim-insx" },

	-- better `%` motion + add `g%`
	{ "andymass/vim-matchup" },

	-- csv
	{
		"mechatroner/rainbow_csv",
		ft = { "csv" }, -- lazy load on filetypes.
	},


	-- open file.txt:42:69 to jump to line 42 and column 69
	{ "wsdjeg/vim-fetch" },

	-- diff on two parts of text
	{ "andrewradev/linediff.vim" },
}

local opts = { -- Lazy options
	checker = {
		enabled = true,
		notify = false,
	}
}

return require("lazy").setup(plugins, opts)
