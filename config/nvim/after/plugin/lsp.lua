if not pcall(require, "lspconfig") then return end
if not pcall(require, "cmp_nvim_lsp") then return end

-- See `:help vim.diagnostic.*` for documentation on any of the below functions
-- local opts = { noremap=true, silent=true }
-- vim.keymap.set("n", "<space>q", vim.diagnostic.open_float, opts)
-- vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
-- vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
-- vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, opts)

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
	-- Enable completion triggered by <c-x><c-o>
	vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

	-- Mappings.
	-- See `:help vim.lsp.*` for documentation on any of the below functions
	local bufopts = { noremap=true, silent=true, buffer=bufnr }
	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
	vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, bufopts)
	vim.keymap.set("n", "gI", vim.lsp.buf.implementation, bufopts)
	vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
	vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
	vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
	vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
	vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
	vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
	vim.keymap.set("n", "<space>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, bufopts)
	vim.keymap.set("n", "<space>D", vim.lsp.buf.type_definition, bufopts)
	vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
	vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
	vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
	vim.keymap.set("n", "<space>f", vim.lsp.buf.formatting, bufopts)
end

local lsp_flags = {
	-- This is the default in Nvim 0.7+
	debounce_text_changes = 150,
}

local lspconfig = require("lspconfig")
local capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities())

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#gopls
lspconfig.gopls.setup{
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
}

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#golangci_lint_ls
if (vim.fn.executable("golangci-lint-langserver") == 0 ) then
	print("Installing golangci-lint-langserver")
	print(vim.fn.system({"go", "install", "github.com/nametake/golangci-lint-langserver@latest"}))
	print(vim.fn.system({"go", "install", "github.com/golangci/golangci-lint/cmd/golangci-lint@latest"}))
end
lspconfig.golangci_lint_ls.setup{
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		command = { "golangci-lint", "run", "--out-format", "json" }
	}
}

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#bashls
if (vim.fn.executable("bash-language-server") == 0 ) then
	print("Installing bash-language-server")
	print(vim.fn.system({"npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "bash-language-server"}))
end
lspconfig.bashls.setup{
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		filetypes = { "sh", "bash"}
	}
}

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#vimls
if (vim.fn.executable("vim-language-server") == 0 ) then
	print("Installing vim-language-server")
	print(vim.fn.system({"npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vim-language-server"}))
end
lspconfig.vimls.setup{
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
}

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#sumneko_lua
-- Get lua-language-server from release and put it in $PATH
-- https://github.com/sumneko/lua-language-server/releases/latest
if (vim.fn.executable("lua-language-server") == 1 ) then
	lspconfig.sumneko_lua.setup{
		capabilities = capabilities,
		flags = lsp_flags,
		on_attach = on_attach,
		settings = {
			Lua = {
				runtime = {
					-- Tell the language server which version of Lua you"re using (most likely LuaJIT in the case of Neovim)
					version = "LuaJIT",
				},
				diagnostics = {
					-- Get the language server to recognize the `vim` global
					globals = {
					"vim",
					"use",
					},
				},
				workspace = {
					-- Make the server aware of Neovim runtime files
					library = vim.api.nvim_get_runtime_file("", true),
				},
				telemetry = {
					-- Do not send telemetry data
					enable = false,
				},
			},
		}
	}
end
