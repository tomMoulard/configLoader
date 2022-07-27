-- Save {{{
vim.keymap.set("n", "<Leader>w", ":update<CR>", {silent=true, remap=false})
vim.keymap.set("n", "<Leader><Leader>", ":update<CR>", {silent=true, remap=false})
-- }}}

-- Strip EOL whitespaces {{{
vim.keymap.set("n", "<Leader>W", ":%s/\\s\\+$//<CR>:let @/=\"\"<CR>", {silent=true, remap=false})
-- }}}

-- splitting windows {{{
vim.keymap.set("n", "<F11>", ":split<CR>", {silent=true})
vim.keymap.set("n", "<F12>", ":vsplit<CR>", {silent=true})
-- }}}

-- auto make {{{
vim.keymap.set("n", "<F5>", ":make<CR><c-w>", {silent=true})
-- }}}

-- Add a matching char {{{
vim.keymap.set("i", "(", "()<C-[>i", {silent=true})
vim.keymap.set("i", "[", "[]<C-[>i", {silent=true})
vim.keymap.set("i", "{", "{}<C-[>i", {silent=true})
vim.keymap.set("i", "<", "<><C-[>i", {silent=true})
-- }}}

-- Turn off search highlighting {{{
vim.keymap.set("n", "<Leader>,", ":nohlsearch<CR>", {silent=true, remap=false})
-- }}}

-- Spell checks {{{
vim.keymap.set("", "<F6>", ":setlocal spell!<CR>", {silent=true})
vim.keymap.set("n", "<Leader>e", "]sz=", {silent=true})
-- }}}

-- Open terminal {{{
vim.keymap.set("n", "<F3>", ":terminal<CR>", {silent=true})
-- }}}

-- Indening code block stays visualy selected {{{
vim.keymap.set("v", "<", "<gv", {silent=true})
vim.keymap.set("v", ">", ">gv", {silent=true})
-- }}}

-- Opennig files even if they don"t exists {{{
vim.keymap.set("", "gf", ":e <cfile><CR>", {silent=true})
-- }}}

-- vim: foldmethod=marker
