if not pcall(require, "gitsigns") then return end

local mapping = require("tm.const").key.mapping

local function on_attach(bufnr)
	local gs = package.loaded.gitsigns

	local function map(mode, l, r, opts)
		opts = opts or {}
		opts.buffer = bufnr
		vim.keymap.set(mode, l, r, opts)
	end

	-- Navigation
	map('n', ']c', function()
		if vim.wo.diff then return ']c' end
		vim.schedule(function() gs.next_hunk() end)
		return '<Ignore>'
	end, { expr = true })

	map('n', '[c', function()
		if vim.wo.diff then return '[c' end
		vim.schedule(function() gs.prev_hunk() end)
		return '<Ignore>'
	end, { expr = true })

	-- Actions
	map('n', mapping.leader .. 'hs', gs.stage_hunk)
	map('n', mapping.leader .. 'hr', gs.reset_hunk)
	map('v', mapping.leader .. 'hs', function() gs.stage_hunk {vim.fn.line('.'), vim.fn.line('v')} end)
	map('v', mapping.leader .. 'hr', function() gs.reset_hunk {vim.fn.line('.'), vim.fn.line('v')} end)
	map('n', mapping.leader .. 'hS', gs.stage_buffer)
	map('n', mapping.leader .. 'hu', gs.undo_stage_hunk)
	map('n', mapping.leader .. 'hR', gs.reset_buffer)
	map('n', mapping.leader .. 'hp', gs.preview_hunk)
	map('n', mapping.leader .. 'hb', function() gs.blame_line { full = true } end)
	map('n', mapping.leader .. 'tb', gs.toggle_current_line_blame)
	map('n', mapping.leader .. 'hd', gs.diffthis)
	map('n', mapping.leader .. 'hD', function() gs.diffthis('~') end)
	map('n', mapping.leader .. 'td', gs.toggle_deleted)

	-- Text object
	map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
end

require('gitsigns').setup({
	signs                        = {
		add                        = { text = '+' },
		change                     = { text = '~' },
		delete                     = { text = '-' },
		topdelete                  = { text = '‾' },
		changedelete               = { text = '~' },
	},
	signcolumn                   = true, -- Toggle with `:Gitsigns toggle_signs`
	numhl                        = false, -- Toggle with `:Gitsigns toggle_numhl`
	linehl                       = false, -- Toggle with `:Gitsigns toggle_linehl`
	word_diff                    = false, -- Toggle with `:Gitsigns toggle_word_diff`
	watch_gitdir                 = {
		interval = 1000,
		follow_files = true
	},
	auto_attach                  = true,
	attach_to_untracked          = false,
	current_line_blame           = true, -- Toggle with `:Gitsigns toggle_current_line_blame`, default false
	current_line_blame_opts      = {
		virt_text = true,
		virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
		delay = 0,
		ignore_whitespace = false,
		virt_text_priority = 100,
	},
	current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
	sign_priority                = 6,
	update_debounce              = 100,
	status_formatter             = nil, -- Use default
	max_file_length              = 40000, -- Disable if file is longer than this (in lines)
	preview_config               = {
		-- Options passed to nvim_open_win
		border = 'single',
		style = 'minimal',
		relative = 'cursor',
		row = 0,
		col = 1
	},
	on_attach                    = on_attach,
})
