local key = require("tm.const").key
local mapping = key.mapping
local mode = key.mode

-- Save {{{
vim.keymap.set(mode.normal, mapping.leader.."w", ":update<CR>", {silent=true, remap=false})
vim.keymap.set(mode.normal, mapping.leader..mapping.leader, ":update<CR>", {silent=true, remap=false})
-- }}}

-- Strip EOL whitespaces {{{
vim.keymap.set(mode.normal, mapping.leader.."W", ":%s/\\s\\+$//<CR>:let @/=\"\"<CR>", {silent=true, remap=false})
-- }}}

-- Splitting windows {{{
vim.keymap.set(mode.normal, mapping.f11, ":split<CR>", {silent=true})
vim.keymap.set(mode.normal, mapping.f12, ":vsplit<CR>", {silent=true})
-- }}}

-- Auto make {{{
vim.keymap.set(mode.normal, mapping.f5, ":make<CR><c-w>", {silent=true})
-- }}}

-- Add a matching char {{{
-- vim.keymap.set(mode.insert, "(", "()<C-[>i", {silent=true})
-- vim.keymap.set(mode.insert, "[", "[]<C-[>i", {silent=true})
-- vim.keymap.set(mode.insert, "{", "{}<C-[>i", {silent=true})
-- vim.keymap.set(mode.insert, "<", "<><C-[>i", {silent=true})
-- }}}

-- Turn off search highlighting {{{
vim.keymap.set(mode.normal, mapping.leader..",", ":nohlsearch<CR>", {silent=true, remap=false})
-- }}}

-- Spell checks {{{
vim.keymap.set(mode.all, mapping.f6, ":setlocal spell!<CR>", {silent=true})
vim.keymap.set(mode.normal, mapping.leader.."e", "]sz=", {silent=true})
-- }}}

-- Open terminal {{{
vim.keymap.set(mode.normal, mapping.f3, ":terminal<CR>", {silent=true})
-- }}}

-- Indening code block stays visualy selected {{{
vim.keymap.set(mode.visual, "<", "<gv", {silent=true})
vim.keymap.set(mode.visual, ">", ">gv", {silent=true})
-- }}}

-- Opennig files even if they don"t exists {{{
vim.keymap.set(mode.all, "gf", ":e <cfile><CR>", {silent=true})
-- }}}

vim.keymap.set(mode.normal, "gcc", ":GoCoverageToggle"..mapping.cr, {})
vim.keymap.set(mode.normal, "gtt", ":GoTest"..mapping.cr, {})
vim.keymap.set(mode.normal, "gtf", ":GoTestFunc"..mapping.cr, {})
-- vim: foldmethod=marker
