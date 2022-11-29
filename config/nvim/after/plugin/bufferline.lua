if not pcall(require, "bufferline") then return end

local function diagnostics_indicator(count, level, diagnostics_dict, context)
	local s = " "
	for e, n in pairs(diagnostics_dict) do
		local sym = e == "error" and " "
			or (e == "warning" and " " or "")
		s = s .. n .. sym
	end
	return s
end

require("bufferline").setup {
	options = {
		offsets = {
			{
				filetype = "NERDTree",
				text = "File Explorer",
				highlight = "Directory",
				text_align = "left"
			}
		},
		diagnostics_indicator = diagnostics_indicator,
	}
}
