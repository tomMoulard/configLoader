-- see :help events for more information
local autocmd_event = {
	BufEnter = "BufEnter",
	BufLeave = "BufLeave",
	BufNewFile = "BufNewFile",
	BufReadPost = "BufReadPost",
	BufWritePre = "BufWritePre",
	FileType = "FileType",
	InsertEnter = "InsertEnter",
	InsertLeave = "InsertLeave",
	WinResized = "WinResized",
}

local key_mode = {
	all = "",
	normal = "n",
	visual = "v",
	insert = "i",
	command = "c",
}

local key_mapping = {
	cr = "<CR>",
	f1 = "<F1>",
	f10 = "<F10>",
	f11 = "<F11>",
	f12 = "<F12>",
	f2 = "<F2>",
	f3 = "<F3>",
	f5 = "<F5>",
	f6 = "<F6>",
	leader = "<leader>",
}

local consts = {
	autocmd = {
		event = autocmd_event,
	},
	key = {
		mapping = key_mapping,
		mode = key_mode,
	},
}

return consts
