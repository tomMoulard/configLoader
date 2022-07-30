-- packer statup install {{{
local install_path = vim.fn.stdpath("data").."/site/pack/packer/start/packer.nvim"
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
	packer_bootstrap = vim.fn.system({"git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path})
end

function packer_sync()
	require("packer").sync()
end
vim.api.nvim_create_autocmd("BufWritePost", {
	desc = "automatically install plugins when updating this file",
	pattern = { os.getenv("HOME") .. "/workspace/configLoader/config/nvim/lua/tm/packer.lua" },
	callback = packer_sync,
})
-- }}}

return require("packer").startup(function()
	use("wbthomason/packer.nvim")

	use("tanvirtin/monokai.nvim")

	use("preservim/nerdcommenter")
	use("preservim/nerdtree")

	use("tpope/vim-fugitive")

	-- grep
	use("nvim-lua/plenary.nvim")
	use("nvim-telescope/telescope.nvim")

	use("nvim-treesitter/nvim-treesitter", {
		run = ":TSUpdate"
	})

	use("neovim/nvim-lspconfig")

	use("github/copilot.vim")

	use("airblade/vim-gitgutter")

	-- autocomplete
	use("hrsh7th/cmp-nvim-lsp")
	use("hrsh7th/cmp-buffer")
	use("hrsh7th/cmp-path")
	use("hrsh7th/cmp-cmdline")
	use("hrsh7th/nvim-cmp")
	use("sirver/UltiSnips")
	use("quangnguyen30192/cmp-nvim-ultisnips")

	use("fatih/vim-go", {
		run = ":GoUpdateBinaries"
	})

	-- use with browser
	use("glacambre/firenvim")

	-- Link with Discord
	use('andweeb/presence.nvim')

	if packer_bootstrap then
		packer_sync()
	end
end)

