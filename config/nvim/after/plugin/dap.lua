if not pcall(require, "dap") then return end

if pcall(require, "dapui") then
	local dapui = require("dapui")
	dapui.setup()
	vim.keymap.set("n", "<F2>", dapui.toggle, {silent=true})
end

-- https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation#go-using-delve-directly
if pcall(require, "dap-go") then
	local dapgo = require("dap-go")
	dapgo.setup()
	vim.keymap.set("n", "<leader>td", dapgo.debug_test, {silent=true})
end
