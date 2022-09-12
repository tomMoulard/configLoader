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

if pcall(require, "lua-dev") then
	-- IMPORTANT: make sure to setup lua-dev BEFORE lspconfig
	require("lua-dev").setup({
		library = {
			enabled = true, -- when not enabled, lua-dev will not change any settings to the LSP server
			-- these settings will be used for your Neovim config directory
			runtime = true, -- runtime path
			types = true, -- full signature, docs and completion of vim.api, vim.treesitter, vim.lsp and others
			plugins = true, -- installed opt or start plugins in packpath
		},
		setup_jsonls = true, -- configures jsonls to provide completion for project specific .luarc.json files
		-- for your Neovim config directory, the config.library settings will be used as is
		-- for plugin directories (root_dirs having a /lua directory), config.library.plugins will be disabled
		-- for any other directory, config.library.enabled will be set to false
		-- override = function(root_dir, options) end,
	})
end

local lsp_flags = {
	-- This is the default in Nvim 0.7+
	debounce_text_changes = 150,
}

local lspconfig = require("lspconfig")
local capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities())

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#gopls
lspconfig.gopls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#golangci_lint_ls
if (vim.fn.executable("golangci-lint-langserver") == 0 ) then
	print("Installing golangci-lint-langserver")
	print(vim.fn.system({"go", "install", "github.com/nametake/golangci-lint-langserver@latest"}))
	print(vim.fn.system({"go", "install", "github.com/golangci/golangci-lint/cmd/golangci-lint@latest"}))
end
lspconfig.golangci_lint_ls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		command = { "golangci-lint", "run", "--out-format", "json" }
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#bashls
if (vim.fn.executable("bash-language-server") == 0 ) then
	print("Installing bash-language-server")
	print(vim.fn.system({"npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "bash-language-server"}))
end
lspconfig.bashls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		filetypes = { "sh", "bash"}
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#vimls
if (vim.fn.executable("vim-language-server") == 0 ) then
	print("Installing vim-language-server")
	print(vim.fn.system({"npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vim-language-server"}))
end
lspconfig.vimls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#sumneko_lua
-- Get lua-language-server from release and put it in $PATH
-- https://github.com/sumneko/lua-language-server/releases/latest
if (vim.fn.executable("lua-language-server") == 1 ) then
	local sumneko_lua_setup = {
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

	if pcall(require, "lua-dev") then
		sumneko_lua_setup.settings.Lua.completion = { callSnippet = "Replace" }
	end

	lspconfig.sumneko_lua.setup(sumneko_lua_setup)
end

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#yamlls
if (vim.fn.executable("yaml-language-server") == 0 ) then
	print("Installing yaml-language-server")
	print(vim.fn.system({"yarn", "global", "add", "yaml-language-server"}))
end
local home = os.getenv("HOME")
lspconfig.yamlls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		yaml = {
			schemas = {
				["https://goreleaser.com/static/schema.json"] = ".goreleaser*.ya?ml",
				["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*.ya?ml",
				["https://json.schemastore.org/golangci-lint.json"] = ".golangci_lint.ya?ml",
				["https://json.schemastore.org/traefik-v2-file-provider.json"] = "traefik*.ya?ml",
				["https://json.schemastore.org/traefik-v2.json"] = "traefik*.ya?ml",
				["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose.*ya?ml",
				[home .. "/go/src/github.com/traefik/hub-agent-kubernetes/hub.traefik.io_accesscontrolpolicies.yaml"] = ".*ya?ml",
			},
		},
		redhat = {
			telemetry = {
				enabled = false
			}
		},
	}
})
