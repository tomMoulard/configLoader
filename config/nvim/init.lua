-- ┌──────────────────┐
-- │╻┏┓╻╻╺┳╸ ╻  ╻ ╻┏━┓│
-- │┃┃┗┫┃ ┃  ┃  ┃ ┃┣━┫│
-- │╹╹ ╹╹ ╹ ╹┗━╸┗━┛╹ ╹│
-- └──────────────────┘
-- Maintainer:
--  tom at moulard dot org
-- Complete_version:
--  You can file the updated version on the git repository
--  github.com/tommoulard/configloader

require("tm")

-- vim.g.degraded_mode = true
vim.g.degraded_mode = false
-- vim.g.pairing_mode = true
vim.g.pairing_mode = false


if vim.g.pairing_mode then
	vim.opt.relativenumber = false
	vim.opt.list = false
end
