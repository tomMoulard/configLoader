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
local on_attach = function(_, bufnr)
	-- Enable completion triggered by <c-x><c-o>
	vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

	-- Mappings.
	-- See `:help vim.lsp.*` for documentation on any of the below functions
	local bufopts = { noremap = true, silent = true, buffer = bufnr }
	vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
	vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, bufopts)
	-- vim.keymap.set("n", "<space>f", vim.lsp.buf.formatting, bufopts)
	vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, bufopts)
	vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
	vim.keymap.set("n", "<space>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, bufopts)
	vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
	vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
	vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
	vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
	vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, bufopts)
	vim.keymap.set("n", "<space>D", vim.diagnostic.open_float, bufopts)
	vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, bufopts)
	vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, bufopts)
	vim.keymap.set("n", "]d", vim.diagnostic.goto_next, bufopts)
end

if pcall(require, "neodev") then
	-- IMPORTANT: make sure to setup neodev BEFORE lspconfig
	local cfg = {
		library = {
			enabled = true, -- when not enabled, neodev will not change any settings to the LSP server
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
	}

	if pcall(require, "nvim-dap-ui") then
		cfg.library.plugins:append("nvim-dap-ui")
	end

	require("neodev").setup(cfg)
end

local lsp_flags = {
	-- This is the default in Nvim 0.7+
	debounce_text_changes = 150,
}

local lspconfig = require("lspconfig")
local capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#gopls
lspconfig.gopls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#golangci_lint_ls
if (vim.fn.executable("golangci-lint-langserver") == 0) then
	vim.notify("Installing golangci-lint-langserver", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/nametake/golangci-lint-langserver@latest" }), vim.log.levels.DEBUG)
	-- vim.notify(vim.fn.system({ "go", "install", "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" }), vim.log.levels.DEBUG)
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
if (vim.fn.executable("bash-language-server") == 0) then
	vim.notify("Installing bash-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "bash-language-server" }), vim.log.levels.DEBUG)
end
lspconfig.bashls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		filetypes = { "sh", "bash" }
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#vimls
if (vim.fn.executable("vim-language-server") == 0) then
	vim.notify("Installing vim-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vim-language-server" }), vim.log.levels.DEBUG)
end
lspconfig.vimls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#lua_ls
-- Get lua-language-server from release and put it in $PATH
-- https://github.com/LuaLs/lua-language-server/releases/latest
if (vim.fn.executable("lua-language-server") == 1) then
	local lua_ls_setup = {
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
					-- https://github.com/neovim/nvim-lspconfig/issues/1700
					checkThirdParty = false,
				},
				telemetry = {
					-- Do not send telemetry data
					enable = false,
				},
			},
		}
	}

	if pcall(require, "neodev") then
		lua_ls_setup.settings.Lua.completion = { callSnippet = "Replace" }
	end

	lspconfig.lua_ls.setup(lua_ls_setup)
end

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#yamlls
if (vim.fn.executable("yaml-language-server") == 0) then
	vim.notify("Installing yaml-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "yarn", "global", "add", "yaml-language-server" }), vim.log.levels.DEBUG)
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
				["kubernetes"] = ".*ya?ml",
			},
		},
		redhat = {
			telemetry = {
				enabled = false
			}
		},
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.txt#dockerls
if (vim.fn.executable("docker-langserver") == 0) then
	vim.notify("Installing docker-langserver", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "dockerfile-language-server-nodejs" }), vim.log.levels.DEBUG)
end
lspconfig.dockerls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

