vim.g.copilot_no_tab_map = true
vim.g.copilot_assume_mapped = true

vim.keymap.set("i", "<C-j>", vim.fn["copilot#Accept"], {silent=true, expr = true, script = true})
