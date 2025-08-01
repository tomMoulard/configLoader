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
	vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

	local const = require("tm.const")
	local event = const.autocmd.event

	vim.api.nvim_create_autocmd(event.BufReadPost, {
		desc = "run ':lua vim.lsp.buf.format' on file save",
		pattern = { "%" },
		callback = vim.lsp.buf.format,
	})

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
			enabled = true,       -- when not enabled, neodev will not change any settings to the LSP server
			-- these settings will be used for your Neovim config directory
			runtime = true,       -- runtime path
			types = true,         -- full signature, docs and completion of vim.api, vim.treesitter, vim.lsp and others
			plugins = { "neotest" }, -- installed opt or start plugins in packpath
		},
		setup_jsonls = true,    -- configures jsonls to provide completion for project specific .luarc.json files
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

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#gopls
lspconfig.gopls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#golangci_lint_ls
if (vim.fn.executable("golangci-lint-langserver") == 0) then
	vim.notify("Installing golangci-lint-langserver", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/nametake/golangci-lint-langserver@latest" }),
		vim.log.levels.DEBUG)
	-- vim.notify(vim.fn.system({ "go", "install", "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" }), vim.log.levels.DEBUG)
end
lspconfig.golangci_lint_ls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	root_dir = lspconfig.util.root_pattern('.git', 'go.mod'),
	init_options = {
		command = { "golangci-lint", "run", "--output.json.path", "stdout", "--show-stats=false", "--issues-exit-code=1" };
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#bashls
-- Can add the following line to disable shellchecks on a given file:
-- # shellcheck disable=SC2034
if (vim.fn.executable("bash-language-server") == 0) then
	vim.notify("Installing bash-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "bash-language-server" }),
		vim.log.levels.DEBUG)
end
lspconfig.bashls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		filetypes = { "sh", "bash" }
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#vimls
if (vim.fn.executable("vim-language-server") == 0) then
	vim.notify("Installing vim-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vim-language-server" }),
		vim.log.levels.DEBUG)
end
lspconfig.vimls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#lua_ls
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

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#yamlls
-- Can add the following line to enable yaml schema support on a given file:
-- # yaml-language-server: $schema=https://json.schemastore.org/yamllint.json
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
				["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*.ya?ml",
				["https://json.schemastore.org/github-action.json"] = ".github/workflows/*.ya?ml",
				["https://json.schemastore.org/dependabot-2.0.json"] = ".github/dependabot.ya?ml",
				["https://json.schemastore.org/golangci-lint.json"] = ".golangci_lint.ya?ml",
				["https://json.schemastore.org/traefik-v2-file-provider.json"] = "traefik*.ya?ml",
				["https://json.schemastore.org/traefik-v2.json"] = "traefik*.ya?ml",
				["https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json"] = ".gitlab-ci.ya?ml",
				["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose.*ya?ml",
				[home .. "/go/src/github.com/traefik/hub-agent-kubernetes/hub.traefik.io_accesscontrolpolicies.yaml"] = ".*ya?ml",
				["kubernetes"] = ".*ya?ml",
				["https://json.schemastore.org/yamllint.json"] = ".yamllint.ya?ml",
			},
			customTags = {
				"!reference sequence",
			},
		},
		redhat = {
			telemetry = {
				enabled = false
			}
		},
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#dockerls
if (vim.fn.executable("docker-langserver") == 0) then
	vim.notify("Installing docker-langserver", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "dockerfile-language-server-nodejs" }),
		vim.log.levels.DEBUG)
end
lspconfig.dockerls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#eslint
if (vim.fn.executable("vscode-eslint-language-server") == 0) then
	vim.notify("Installing eslint", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vscode-langservers-extracted" }),
		vim.log.levels.DEBUG)
end
lspconfig.eslint.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = function(client, bufnr)
		vim.api.nvim_create_autocmd("BufWritePre", {
			buffer = bufnr,
			command = "EslintFixAll",
		})
	end,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#ts_ls
if (vim.fn.executable("typescript-language-server") == 0) then
	vim.notify("Installing ts_ls", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "typescript-language-server" }),
		vim.log.levels.DEBUG)
end
lspconfig.ts_ls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#tailwindcss
if (vim.fn.executable("tailwindcss-language-server") == 0) then
	vim.notify("Installing tailwindcss", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "@tailwindcss/language-server" }),
		vim.log.levels.DEBUG)
end
lspconfig.tailwindcss.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#pylsp
if (vim.fn.executable("pylsp") == 0) then
	vim.notify("Installing pytlsp", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-server[all]" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-black" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-isort" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-ruff" }), vim.log.levels.DEBUG)
end
lspconfig.pylsp.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		pylsp = {
			plugins = {
				pycodestyle = {
					ignore = { 'E501' },
					-- maxLineLength = 100
				},
				pylint = {
					enabled = true,
					args = {
						-- "--disable E501",
					}
				},
				pydocstyle = {
					enabled = true,
				},
				black = {
					enabled = true,
				},
				isort = {
					enabled = true,
				},
				ruff = {
					enabled = true,
				},
			}
		}
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#dartls
-- if (vim.fn.executable("pylsp") == 0) then
-- vim.notify("Installing pytlsp", vim.log.levels.INFO)
-- vim.notify(vim.fn.system({ "pip", "install", "python-lsp-server[all]" }), vim.log.levels.DEBUG)
-- end
lspconfig.dartls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		dart = {
			closingLabels = true,
			flutterOutline = true,
			onlyAnalyzeProjectsWithOpenFiles = true,
			outline = true,
			suggestFromUnimportedLibraries = true,
			completeFunctionCalls = true,
			showTodos = true
		}
	}
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#java_language_server
lspconfig.java_language_server.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	cmd = { "/Users/tom.moulard/workspace/java-language-server/dist/lang_server_mac.sh" },
	root_dir = lspconfig.util.root_pattern("pom.xml", "gradle.build", ".git"),
	filetypes = { "java" },
	settings = {},
})

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#terraform_lsp
if (vim.fn.executable("terraform-ls") == 0) then
	vim.notify("Installing terraform-ls", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/hashicorp/terraform-ls@latest" }), vim.log.levels.DEBUG)
end
lspconfig.terraformls.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
})


-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.txt#rust_analyzer
if (vim.fn.executable("rust-analyzer") == 0) then
vim.notify("Installing rust-analyzer", vim.log.levels.INFO)
vim.notify(vim.fn.system({"rustup", "component", "add", "rust-analyzer", "rust-src"}), vim.log.levels.DEBUG)
end
lspconfig.rust_analyzer.setup({
	capabilities = capabilities,
	flags = lsp_flags,
	on_attach = on_attach,
	settings = {
		['rust-analyzer'] = {
			diagnostics = {
				enable = false,
			},
			imports = {
				granularity = {
					group = "module",
				},
				prefix = "self",
			},
			cargo = {
				buildScripts = {
					enable = true,
				},
			},
			procMacro = {
				enable = true
			},
		}
	}
})
