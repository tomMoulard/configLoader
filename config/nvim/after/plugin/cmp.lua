if not pcall(require, "cmp") then return end

local function format(entry, vim_item)
	if entry.source.name == "nvim_lsp" then
		vim_item.menu = '{' .. entry.source.source.client.name .. '}'
	else
		vim_item.menu = '[' .. entry.source.name .. ']'
	end

	return vim_item
end

local cmp = require("cmp")

cmp.setup({
	snippet = {
		expand = function(args)
			vim.fn["UltiSnips#Anon"](args.body)
		end,
	},
	window = {
		-- completion = cmp.config.window.bordered(),
		-- documentation = cmp.config.window.bordered(),
	},
	mapping = cmp.mapping.preset.insert({
		["<Tab>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
		["<S-Tab>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-e>"] = cmp.mapping.abort(),
		["<C-f>"] = cmp.mapping.scroll_docs(4),
		["<C-b>"] = cmp.mapping.scroll_docs(-4),
		["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
	}),
	sources = cmp.config.sources(
		{
			{ name = "nvim_lsp" },
			{ name = "nvim_lua" },
			{
				name = "lazydev",
				group_index = 0, -- set group index to 0 to skip loading LuaLS completions
			},
			{ name = "ultisnips" },
			{
				name = "path",
				options = {
					trailing_slash = true
				},
			},
			{ name = 'nvim_lsp_signature_help' },
			{ name = "buffer" },
			{ name = 'treesitter' },
		},
		{
			{ name = "buffer" },
		}
	),
	formatting = {
		format = format,
	}
})

vim.opt.completeopt = { "menu", "menuone", "noselect" }
