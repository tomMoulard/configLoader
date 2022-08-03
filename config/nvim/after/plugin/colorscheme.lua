if not pcall(require, "monokai") then return end

if vim.g.degraded_mode then return end

local monokai = require("monokai")

monokai.setup {
	palette = monokai.pro
	-- palette = monokai.soda
	-- palette = monokai.ristretto
}

-- Transparent background color
vim.cmd("highlight Normal guibg=none")
