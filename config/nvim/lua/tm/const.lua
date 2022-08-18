local autocmd_event = {
	BufNewFile = "BufNewFile",
	BufReadPost = "BufReadPost",
	BufWritePre = "BufWritePre",
	FileType = "FileType",
}

local mapping = {
	leader = "<leader",
	f2 = "<F2>",
}

local consts = {
	Autocmd_event = autocmd_event,
	Mapping = mapping,
}

return consts
