-- packer statup install {{{
local install_path = vim.fn.stdpath("data").."/site/pack/packer/start/packer.nvim"
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
	local packer_bootstrap = vim.fn.system({"git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path})
end

-- TODO: source file before sync
local function packer_sync()
	require("packer").sync()
end
-- FIXME: solve packer_sync TODO
-- vim.api.nvim_create_autocmd("BufWritePost", {
-- desc = "automatically install plugins when updating this file",
-- pattern = { os.getenv("HOME") .. "/workspace/configLoader/config/nvim/lua/tm/packer.lua" },
-- callback = packer_sync,
-- })
-- }}}

return require("packer").startup(function()
	use("wbthomason/packer.nvim") -- plugin manager.

	use("tanvirtin/monokai.nvim") -- color scheme.

	use("preservim/nerdcommenter") -- comment input.
	use("preservim/nerdtree") -- <F1>

	use("tpope/vim-fugitive")

	-- grep
	use("nvim-lua/plenary.nvim")
	use("nvim-telescope/telescope.nvim") -- find files or content.

	-- parser generator tool and an incremental parsing library.
	use("nvim-treesitter/nvim-treesitter", {
		run = ":TSUpdate"
	})
	use("nvim-treesitter/nvim-treesitter-context")

	use("neovim/nvim-lspconfig")

	use("github/copilot.vim") -- AI powered completion.

	use("lewis6991/gitsigns.nvim") -- shows git status.

	-- autocomplete
	use("hrsh7th/cmp-buffer") -- autocomplete strings in buffer.
	use("hrsh7th/cmp-cmdline") -- nvim-cmp source for vim's cmdline.
	use("hrsh7th/cmp-nvim-lsp") -- nvim-cmp source for neovim's built-in language server client.
	use("hrsh7th/cmp-nvim-lsp-signature-help") -- nvim-cmp source for displaying function signatures with the current parameter emphasized.
	use("hrsh7th/cmp-nvim-lua") -- nvim-cmp source for neovim Lua API.
	use("hrsh7th/cmp-path") -- autocomplete file paths.
	use("hrsh7th/nvim-cmp")
	use("quangnguyen30192/cmp-nvim-ultisnips") -- use snippets from UltiSnips in nvim-cmp.
	use("sirver/UltiSnips") -- snippets

	use("fatih/vim-go", {
		run = ":GoUpdateBinaries"
	})

	use("glacambre/firenvim", {
		run = function() vim.fn['firenvim#install'](0) end
	}) -- use with browser

	use('andweeb/presence.nvim') -- Link with Discord.

	-- Debug Adapter Protocol
	use({
		"leoluz/nvim-dap-go", -- Go Delve debugger.
		"rcarriga/nvim-dap-ui", -- UI for DAP.
		requires = {"mfussenegger/nvim-dap"}
	})

	if packer_bootstrap then
		packer_sync()
	end
end)

