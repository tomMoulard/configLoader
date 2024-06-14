-- Firenvim configuration
-- firenvim is disabled by default. Press <C-S-e> to turn the currently focused
-- element into a neovim iframe.
-- To configure the browser behavior, go to chrome:/extensions/shortcuts and click on
-- 'keyboard shortcuts', and set Firenvim keybindings.

-- https://github.com/glacambre/firenvim?tab=readme-ov-file#understanding-firenvims-configuration-object
-- https://github.com/glacambre/firenvim/blob/e412ab23c5b56b7eb3c361da8a1f8a2e94c51001/src/utils/configuration.ts#L108
vim.g.firenvim_config = {
	globalSettings = {
		alt = "all",
		ignoreKeys = {
			all = { "<C-T>", "<C-S-T>", "<C-w>" },
		}
	},
	localSettings = {
		[".*"] = {
			cmdline  = "neovim",
			content  = "text",
			priority = 0,
			selector = 'textarea:not([readonly], [aria-readonly]), div[role="textbox"]',
			takeover = "never", -- default: always
			filename = "{hostname%32}_{pathname%32}_{selector%32}_{timestamp%32}.{extension}"
		}
	}
}

if not vim.g.started_by_firenvim then return end

local const = require("tm.const")
local event = const.autocmd.event

vim.opt.laststatus = 0

-- Custom filetypes for sites {{{
vim.api.nvim_create_autocmd(event.BufEnter, {
    pattern = "github.com_*.txt",
    command = "set filetype=markdown"
})
-- }}}
