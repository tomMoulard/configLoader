local autocmd_event = {
	BufNewFile = "BufNewFile",
	BufReadPost = "BufReadPost",
	BufWritePre = "BufWritePre",
	FileType = "FileType",
}

local key_mode = {
	all = "",
	normal = "n",
	visual = "v",
	insert = "i",
}

local key_mapping = {
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
