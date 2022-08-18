local mapping = require("tm.const").Mapping

-- Save {{{
vim.keymap.set("n", mapping.leader.."w", ":update<CR>", {silent=true, remap=false})
vim.keymap.set("n", mapping.leader..mapping.leader, ":update<CR>", {silent=true, remap=false})
-- }}}

-- Strip EOL whitespaces {{{
vim.keymap.set("n", mapping.leader.."W", ":%s/\\s\\+$//<CR>:let @/=\"\"<CR>", {silent=true, remap=false})
-- }}}

-- Splitting windows {{{
vim.keymap.set("n", mapping.f11, ":split<CR>", {silent=true})
vim.keymap.set("n", mapping.f12, ":vsplit<CR>", {silent=true})
-- }}}

-- Auto make {{{
vim.keymap.set("n", mapping.f5, ":make<CR><c-w>", {silent=true})
-- }}}

-- Add a matching char {{{
-- vim.keymap.set("i", "(", "()<C-[>i", {silent=true})
-- vim.keymap.set("i", "[", "[]<C-[>i", {silent=true})
-- vim.keymap.set("i", "{", "{}<C-[>i", {silent=true})
-- vim.keymap.set("i", "<", "<><C-[>i", {silent=true})
-- }}}

-- Turn off search highlighting {{{
vim.keymap.set("n", mapping.leader..",", ":nohlsearch<CR>", {silent=true, remap=false})
-- }}}

-- Spell checks {{{
vim.keymap.set("", mapping.f6, ":setlocal spell!<CR>", {silent=true})
vim.keymap.set("n", mapping.leader.."e", "]sz=", {silent=true})
-- }}}

-- Open terminal {{{
vim.keymap.set("n", mapping.f3, ":terminal<CR>", {silent=true})
-- }}}

-- Indening code block stays visualy selected {{{
vim.keymap.set("v", "<", "<gv", {silent=true})
vim.keymap.set("v", ">", ">gv", {silent=true})
-- }}}

-- Opennig files even if they don"t exists {{{
vim.keymap.set("", "gf", ":e <cfile><CR>", {silent=true})
-- }}}

-- vim: foldmethod=marker
