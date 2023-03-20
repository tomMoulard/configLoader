if not pcall(require, "dap") then return end

local mapping = require("tm.const").key.mapping

if pcall(require, "dapui") then
	local dapui = require("dapui")
	dapui.setup()
	vim.keymap.set("n", mapping.f2, dapui.toggle, { silent = true })
end

-- https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation#go-using-delve-directly
if pcall(require, "dap-go") then
	local dapgo = require("dap-go")
	dapgo.setup({
		dap_configurations = {
			{
				-- Must be "go" or it will be ignored by the plugin
				type = "go",
				name = "Attach remote",
				mode = "remote",
				request = "attach",
			},
		},
		-- delve configurations
		delve = {
			-- time to wait for delve to initialize the debug session.
			-- default to 20 seconds
			initialize_timeout_sec = 20,
			-- a string that defines the port to start delve debugger.
			-- default to string "${port}" which instructs nvim-dap
			-- to start the process in a random available port
			port = "${port}"
		},
	})
	vim.keymap.set("n", mapping.leader .. "td", dapgo.debug_test, { silent = true })
end

if pcall(require, "nvim-dap-virtual-text") then
	require("nvim-dap-virtual-text").setup({
		enabled = true, -- enable this plugin (the default)
	})
end

-- see :help dap-mapping
vim.keymap.set('n', mapping.f5, function() require('dap').continue() end)
vim.keymap.set('n', mapping.f10, function() require('dap').step_over() end)
vim.keymap.set('n', mapping.f11, function() require('dap').step_into() end)
vim.keymap.set('n', mapping.f12, function() require('dap').step_out() end)
vim.keymap.set('n', mapping.leader .. 'b', function() require('dap').toggle_breakpoint() end)
vim.keymap.set('n', mapping.leader .. 'B', function() require('dap').set_breakpoint() end)
vim.keymap.set('n', mapping.leader .. 'lp', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end)
vim.keymap.set('n', mapping.leader .. 'dr', function() require('dap').repl.open() end)
vim.keymap.set('n', mapping.leader .. 'dl', function() require('dap').run_last() end)
vim.keymap.set({'n', 'v'}, mapping.leader .. 'dh', function() require('dap.ui.widgets').hover() end)
vim.keymap.set({'n', 'v'}, mapping.leader .. 'dp', function() require('dap.ui.widgets').preview() end)
vim.keymap.set('n', mapping.leader .. 'df', function()
	local widgets = require('dap.ui.widgets')
	widgets.centered_float(widgets.frames)
end)
vim.keymap.set('n', mapping.leader .. 'ds', function()
	local widgets = require('dap.ui.widgets')
	widgets.centered_float(widgets.scopes)
end)

