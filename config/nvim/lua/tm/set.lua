vim.opt.compatible = false

vim.g.mapleader = " "

-- mouse {{{
vim.opt.mouse = ""
-- }}}

-- Indendation {{{
vim.opt.autoindent = true
vim.opt.breakindent = true
vim.opt.copyindent = true
vim.opt.expandtab = false
vim.opt.shiftround = true
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.smarttab = true
vim.opt.softtabstop = 2
vim.opt.tabstop = 2
-- }}}

-- Folds {{{
vim.opt.foldenable = false
vim.opt.foldlevel = 999
vim.opt.foldmethod = "expr"
-- }}}

-- Undo {{{
vim.opt.history = 1000
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true
vim.opt.undolevels = 1000
-- }}}

-- file stuff {{{
vim.opt.autoread = false
vim.opt.autowrite = false
vim.opt.autowriteall = false
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"
vim.opt.fileformats = { "unix", "dos", "mac" }
vim.opt.linebreak = false
vim.opt.secure = true
vim.opt.spelllang = { "fr", "en_us" }
vim.opt.wrap = false
-- }}}

-- Searching and patterns {{{
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.incsearch = true
vim.opt.magic = true
vim.opt.showmatch = true
vim.opt.smartcase = true
-- }}}

-- Styles {{{
vim.opt.cmdheight = 1
vim.opt.colorcolumn = "80,+0"
vim.opt.cursorcolumn = false
vim.opt.cursorline = true
vim.opt.lazyredraw = true
vim.opt.list = true
vim.opt.listchars = "tab:»·,trail:¶,eol: ,extends:>,precedes:<,nbsp:¤"
vim.opt.number = true
vim.opt.ruler = true
vim.opt.rulerformat = "%15(%c%V %p%%%)"
vim.opt.scrolloff = 5
vim.opt.sidescroll = 5
vim.opt.sidescrolloff = 5
vim.opt.statusline = "%<%f (%{&ft})%=%-19(%3l,%02c-0x%02B%)"
vim.opt.termguicolors = true
vim.opt.title = true
-- }}}

-- Complete {{{
vim.opt.infercase = true
-- }}}


-- Timeouts {{{
vim.opt.timeoutlen = 1500
vim.opt.ttimeoutlen = 1500
-- }}}

-- Clipboard {{{
vim.opt.clipboard = "unnamedplus"
-- }}}

-- stop vim from adding a newline at end of file {{{
-- https://stackoverflow.com/a/16114535
vim.opt.fixendofline = false
-- }}}

-- vim: foldmethod=marker
