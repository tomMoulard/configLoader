local const = require("tm.const")
local event = const.Autocmd_event

local function ft_autocmd(pattern, command, value)
	vim.api.nvim_create_autocmd(event.FileType, {
		pattern = pattern,
		callback = function() command:append(value) end,
	})
end

-- Matchpairs {{{
ft_autocmd({"c", "cpp", "java"}, vim.opt.matchpairs, ":;")
ft_autocmd({"html"}, vim.opt.matchpairs, "<:>")
-- }}}

-- Make {{{
ft_autocmd({"html"}, vim.opt.makeprg, "tidy -e -q --gnu-emacs 1 % $*")
ft_autocmd({"markdown"}, vim.opt.makeprg, "pandoc % $* -o %.pdf")
ft_autocmd({"css"}, vim.opt.makeprg, "npx prettier --write %")
ft_autocmd({"sh"}, vim.opt.makeprg, "shellcheck -f gcc % $*")
-- }}}

-- Proper comments {{{
ft_autocmd({"python", "sh"}, vim.opt.commentstring, "# %s")
ft_autocmd({"html"}, vim.opt.commentstring, "<!-- %s -->")
ft_autocmd({"c"}, vim.opt.commentstring, "/* %s */")
ft_autocmd({"go"}, vim.opt.commentstring, "// %s")
ft_autocmd({"xdefaults"}, vim.opt.commentstring, "! %s")
ft_autocmd({"vim"}, vim.opt.commentstring, "\" %s")
ft_autocmd({"sql"}, vim.opt.commentstring, "-- %s")
-- }}}

-- Linting {{{
-- vim.api.nvim_create_autocmd(BufWritePre, {
	-- desc = "Formating go files on save",
	-- pattern = { "*.go" },
	-- callback = vim.lsp.buf.formatting,
-- })
-- }}}

-- Cursor position restore {{{
-- When editing a file, always jump to the last known cursor position.
-- Don't do it when the position is invalid or when inside an event handler
-- (happens when dropping a file on gvim).
-- Also don't do it when the mark is in the first line, that is the default
-- position when opening a file.
local function jump_to_last_position()
	local curr_line = vim.fn.line("'\"")
	if (curr_line > 1 and curr_line <= vim.fn.line("$")) then
		print(vim.api.nvim_exec("normal! g`\"", true))
	end
end
vim.api.nvim_create_autocmd(event.BufReadPost, {
	desc = "Jump to last known cursor position when opening a file",
	pattern = { "*" },
	callback = jump_to_last_position,
	-- command = 'if line("\'\"") > 1 && line("\'\"") <= line("$") | exe "normal! g`\"" | endif',
})
-- }}}

-- skeleton files {{{
-- vim-go already does that
-- vim.api.nvim_create_autocmd(BufNewFile, {
	-- desc = "Read skeleton file when opening a new file",
	-- pattern = { "*.go" },
	-- command = "lua vim.api.nvim_exec('0r ~/workspace/default_files/go/main.go', true)",
-- })
-- }}}

-- vim: fdm=marker
