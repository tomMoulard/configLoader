local const = require("tm.const")
local event = const.autocmd.event

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local bufnr = args.buf
		vim.lsp.inlay_hint.enable(true)

		vim.api.nvim_create_autocmd(event.BufWritePre, {
			desc = "Format file on save via LSP",
			buffer = bufnr,
			callback = function()
				local clients = vim.lsp.get_clients({
					bufnr = bufnr,
					method = vim.lsp.protocol.Methods.textDocument_formatting,
				})
				if #clients > 0 then
					vim.lsp.buf.format({ bufnr = bufnr })
				end
			end,
		})

		-- Mappings.
		-- Built-in defaults in 0.12: K (hover), gra (code_action), grn (rename),
		-- grr (references), gri (implementation), grt (type_definition),
		local bufopts = { noremap = true, silent = true, buffer = bufnr }
		vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)
		vim.keymap.set("n", "<space>wa", vim.lsp.buf.add_workspace_folder, bufopts)
		vim.keymap.set("n", "<space>wl", function()
			print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, bufopts)
		vim.keymap.set("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
		vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
		vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, bufopts)
		vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, bufopts)
		vim.keymap.set("n", "<space>D", vim.diagnostic.open_float, bufopts)
		vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist, bufopts)
	end
})

if pcall(require, "lazydev") then require("lazydev").setup({}) end

local capabilities = {}
if pcall(require, "cmp_nvim_lsp") then
	capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
end

-- Go language server configuration
vim.lsp.config["gopls"] = {
	cmd = { "gopls" },
	filetypes = { "go", "gomod", "gowork", "gotmpl" },
	capabilities = capabilities,
}
vim.lsp.enable("gopls")


-- GolangCI-Lint language server configuration
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#golangci_lint_ls
if (vim.fn.executable("golangci-lint-langserver") == 0) then
	vim.notify("Installing golangci-lint-langserver", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/nametake/golangci-lint-langserver@latest" }),
		vim.log.levels.DEBUG)
	-- vim.notify(vim.fn.system({ "go", "install", "github.com/golangci/golangci-lint/cmd/golangci-lint@latest" }), vim.log.levels.DEBUG)
end
vim.lsp.config["golangci_lint_ls"] = {
	cmd = { "golangci-lint-langserver" },
	filetypes = { "go", "gomod" },
	capabilities = capabilities,
	root_markers = { ".golangci.yml", ".golangci.yaml", ".golangci.toml", ".golangci.json", "go.work", "go.mod", ".git" },
	init_options = {
		command = { "golangci-lint", "run", "--output.json.path=stdout", "--show-stats=false" },

	}
}
vim.lsp.enable("golangci_lint_ls")

-- Bash language server configuration
-- Can add the following line to disable shellchecks on a given file:
-- # shellcheck disable=SC2034
if (vim.fn.executable("bash-language-server") == 0) then
	vim.notify("Installing bash-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "bash-language-server" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["bashls"] = {
	cmd = { "bash-language-server", "start" },
	filetypes = { "sh", "bash" },
	capabilities = capabilities,
}
vim.lsp.enable("bashls")

-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#vimls
if (vim.fn.executable("vim-language-server") == 0) then
	vim.notify("Installing vim-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vim-language-server" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["vimls"] = {
	cmd = { "vim-language-server", "--stdio" },
	filetypes = { "vim", "vimdoc" },
	capabilities = capabilities,
}
vim.lsp.enable("vimls")

-- Lua language server configuration
-- Get lua-language-server from release and put it in $PATH
-- https://github.com/LuaLs/lua-language-server/releases/latest
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#lua_ls
if (vim.fn.executable("lua-language-server") == 1) then
	local lua_ls_setup = {
		cmd = { "lua-language-server" },
		on_init = function(client)
			if client.workspace_folders then
				local path = client.workspace_folders[1].name
				if
						path ~= vim.fn.stdpath('config')
						and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
				then
					return
				end
			end

			client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
				runtime = {
					-- Tell the language server which version of Lua you're using (most
					-- likely LuaJIT in the case of Neovim)
					version = 'LuaJIT',
					-- Tell the language server how to find Lua modules same way as Neovim
					-- (see `:h lua-module-load`)
					path = {
						'lua/?.lua',
						'lua/?/init.lua',
					},
				},
				-- Make the server aware of Neovim runtime files
				workspace = {
					checkThirdParty = false,
					library = {
						vim.env.VIMRUNTIME
						-- Depending on the usage, you might want to add additional paths
						-- here.
						-- '${3rd}/luv/library'
						-- '${3rd}/busted/library'
					}
					-- Or pull in all of 'runtimepath'.
					-- NOTE: this is a lot slower and will cause issues when working on
					-- your own configuration.
					-- See https://github.com/neovim/nvim-lspconfig/issues/3189
					-- library = {
					--   vim.api.nvim_get_runtime_file('', true),
					-- }
				}
			})
		end,
		capabilities = capabilities,
		filetypes = { "lua" },
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
					-- Disable third-party library checking for better performance
					checkThirdParty = false,
				},
				telemetry = {
					-- Do not send telemetry data
					enable = false,
				},
			},
		}
	}

	if pcall(require, "lazydev") then
		lua_ls_setup.settings.Lua.completion = { callSnippet = "Replace" }
	end

	vim.lsp.config["lua_ls"] = lua_ls_setup
	vim.lsp.enable("lua_ls")

	-- Ensure lua_ls starts for all lua files
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "lua",
		callback = function()
			vim.lsp.start({
				name = "lua_ls",
				cmd = { "lua-language-server" },
			})
		end,
	})
end


-- YAML language server configuration
-- Can add the following line to enable yaml schema support on a given file:
-- # yaml-language-server: $schema=https://json.schemastore.org/yamllint.json
if (vim.fn.executable("yaml-language-server") == 0) then
	vim.notify("Installing yaml-language-server", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "yarn", "global", "add", "yaml-language-server" }), vim.log.levels.DEBUG)
end
local home = os.getenv("HOME")
vim.lsp.config["yamlls"] = {
	cmd = { "yaml-language-server", "--stdio" },
	filetypes = { "yaml", "yaml.docker-compose" },
	capabilities = capabilities,
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
				["https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json"] =
				".gitlab-ci.ya?ml",
				["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] =
				"docker-compose.*ya?ml",
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
}
vim.lsp.enable("yamlls")

-- Docker language server configuration
if (vim.fn.executable("docker-langserver") == 0) then
	vim.notify("Installing docker-langserver", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "dockerfile-language-server-nodejs" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["dockerls"] = {
	cmd = { "docker-langserver", "--stdio" },
	filetypes = { "dockerfile" },
	capabilities = capabilities,
}
vim.lsp.enable("dockerls")

-- ESLint language server configuration
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#eslint
if (vim.fn.executable("vscode-eslint-language-server") == 0) then
	vim.notify("Installing eslint", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "vscode-langservers-extracted" }),
		vim.log.levels.DEBUG)
end

vim.lsp.config["eslint"] = {
	cmd = { "vscode-eslint-language-server", "--stdio" },
	filetypes = { "javascript", "javascriptreact", "mdx", "typescript", "typescriptreact", "vue", "svelte" },
	capabilities = capabilities,
	on_attach = function(client, bufnr)
		vim.api.nvim_create_autocmd("BufWritePre", {
			buffer = bufnr,
			callback = function()
				client:request_sync('workspace/executeCommand', {
					command = 'eslint.applyAllFixes',
					arguments = {
						{
							uri = vim.uri_from_bufnr(bufnr),
						},
					},
				}, nil, bufnr)
			end,
		})
	end,
	settings = {
	},
}
-- vim.lsp.enable("eslint")

-- TypeScript language server configuration
if (vim.fn.executable("typescript-language-server") == 0) then
	vim.notify("Installing ts_ls", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "typescript-language-server" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["ts_ls"] = {
	cmd = { "typescript-language-server", "--stdio" },
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	capabilities = capabilities,
}
vim.lsp.enable("ts_ls")

-- MDX language server configuration
-- https://github.com/mdx-js/mdx-analyzer
if (vim.fn.executable("mdx-language-server") == 0) then
	vim.notify("Installing mdx-language-server", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "@mdx-js/language-server" }),
		vim.log.levels.DEBUG)
end
local function get_tsdk()
	-- Prefer workspace-local TypeScript
	local local_tsdk = vim.fn.getcwd() .. "/node_modules/typescript/lib"
	if vim.uv.fs_stat(local_tsdk) then return local_tsdk end
	-- Fall back to the global npm root (where tsc lives)
	local global_root = vim.trim(vim.fn.system({ "npm", "root", "--global" }))
	return global_root .. "/typescript/lib"
end
vim.lsp.config["mdx_analyzer"] = {
	cmd = { "mdx-language-server", "--stdio" },
	filetypes = { "mdx" },
	capabilities = capabilities,
	init_options = {
		typescript = {
			tsdk = get_tsdk(),
		},
	},
}
vim.lsp.enable("mdx_analyzer")

-- TailwindCSS language server configuration
if (vim.fn.executable("tailwindcss-language-server") == 0) then
	vim.notify("Installing tailwindcss", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "@tailwindcss/language-server" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["tailwindcss"] = {
	cmd = { "tailwindcss-language-server", "--stdio" },
	filetypes = { "html", "css", "scss", "javascript", "javascriptreact", "mdx", "typescript", "typescriptreact", "vue", "svelte" },
	capabilities = capabilities,
}
vim.lsp.enable("tailwindcss")

-- Python language server configuration
if (vim.fn.executable("pylsp") == 0) then
	vim.notify("Installing pytlsp", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-server[all]" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-black" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-isort" }), vim.log.levels.DEBUG)
	vim.notify(vim.fn.system({ "pip", "install", "python-lsp-ruff" }), vim.log.levels.DEBUG)
end
vim.lsp.config["pylsp"] = {
	cmd = { "pylsp" },
	filetypes = { "python" },
	capabilities = capabilities,
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
}
vim.lsp.enable("pylsp")

-- Dart language server configuration
if (vim.fn.executable("dart") == 1) then
	vim.lsp.config["dartls"] = {
		cmd = { "dart", "language-server", "--protocol=lsp" },
		filetypes = { "dart" },
		capabilities = capabilities,
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
	}
	vim.lsp.enable("dartls")
end

-- Java language server configuration
vim.lsp.config["java_language_server"] = {
	capabilities = capabilities,
	cmd = { "/Users/tom.moulard/workspace/java-language-server/dist/lang_server_mac.sh" },
	root_markers = { '.git', 'pom.xml', 'gradle.build' },
	filetypes = { "java" },
	settings = {},
}
vim.lsp.enable("java_language_server")

-- Terraform language server configuration
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#terraformls
if (vim.fn.executable("terraform-ls") == 0) then
	vim.notify("Installing terraform-ls", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/hashicorp/terraform-ls@latest" }), vim.log.levels.DEBUG)
end
vim.lsp.config["terraformls"] = {
	cmd = { "terraform-ls", "serve" },
	filetypes = { "terraform", "tf", "tfvars", "terraform-vars" },
	root_markers = { ".terraform", ".git" },
	capabilities = capabilities,
	init_options = {
		ignoreSingleFileWarning = true,
	},
}
vim.lsp.enable("terraformls")

-- tflint language server configuration
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#tflint
if (vim.fn.executable("tflint") == 0) then
	vim.notify("Installing tflint", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "go", "install", "github.com/terraform-linters/tflint@latest" }), vim.log.levels.DEBUG)
end
vim.lsp.config["tflint"] = {
	cmd = { "tflint", "--langserver" },
	filetypes = { "terraform", "tf", "tfvars", "terraform-vars" },
	capabilities = capabilities,
}
vim.lsp.enable("tflint")

-- Rust analyzer language server configuration
if (vim.fn.executable("rust-analyzer") == 0) then
	vim.notify("Installing rust-analyzer", vim.log.levels.INFO)
	vim.notify(vim.fn.system({ "rustup", "component", "add", "rust-analyzer", "rust-src" }), vim.log.levels.DEBUG)
end
vim.lsp.config["rust_analyzer"] = {
	cmd = { "rust-analyzer" },
	filetypes = { "rust" },
	capabilities = capabilities,
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
}
vim.lsp.enable("rust_analyzer")

-- GitHub Copilot language server (inline completion)
-- Install: npm install -g @github/copilot-language-server
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#copilot
if (vim.fn.executable("copilot-language-server") == 0) then
	vim.notify("Installing copilot-language-server", vim.log.levels.INFO)
	vim.notify(
		vim.fn.system({ "npm", "install", "--global", "--prefix", vim.fn.stdpath("data"), "@github/copilot-language-server" }),
		vim.log.levels.DEBUG)
end
vim.lsp.config["copilot"] = {
	cmd = { "copilot-language-server", "--stdio" },
	capabilities = capabilities,
	root_markers = { ".git" },
	init_options = {
		editorInfo = {
			name = "neovim",
			version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
		},
		editorPluginInfo = {
			name = "copilot-lsp",
			version = "0.1.0",
		},
	},
	settings = {},
}
vim.lsp.enable("copilot")

vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(args)
		local bufnr = args.buf
		local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

		if client.name == "copilot" or client:supports_method(vim.lsp.protocol.Methods.textDocument_inlineCompletion, bufnr) then
			vim.lsp.inline_completion.enable(true, { bufnr = bufnr })

			vim.keymap.set(const.key.mode.insert, '<C-J>',
				vim.lsp.inline_completion.get,
				{ desc = 'LSP: accept inline completion', buffer = bufnr }
			)
			vim.keymap.set(const.key.mode.insert, '<C-L>',
				vim.lsp.inline_completion.select,
				{ desc = 'LSP: switch inline completion', buffer = bufnr }
			)
		end
	end
})
