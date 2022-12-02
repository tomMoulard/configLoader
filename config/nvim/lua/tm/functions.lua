local M = {}
-- Helpers {{{
-- function print_table(table)
-- for k, v in pairs(table) do
-- print(k, v)
-- end
-- end
-- }}}

-- Pretty file on call {{{
function JsonPretty()
	vim.api.nvim_command(":%!python -m json.tool")
end

vim.api.nvim_create_user_command("JsonPretty", JsonPretty, {})
-- }}}

-- GitHub related {{{
-- TODO: implement auto complete with available repos
-- see :command-complete
local gh = {}
-- helper{{{
function gh.parse_and_put(lines)
	local json = vim.json.decode(lines)
	for _, value in ipairs(json) do
		vim.api.nvim_put({ string.format("|%6d|%s|%s||", value.number, value.updatedAt, value.title) }, "l", true, false)
	end
end

function gh.get_current_date()
	local num_of_days = 1
	print("Today is Tuesday", os.date("*t").wday)
	if os.date("*t").wday == 2 then
		num_of_days = 3
	end

	-- 60 * 60 * 24 = 86400
	return os.date("%Y-%m-%dT%X", os.time() - 86400 * num_of_days)
end

-- }}}
-- Input daily issues {{{
function gh.input_daily_issues(args)
	local repo = os.getenv("HOME") .. "/go/src/github.com/traefik/traefik"
	if args.args:len() > 0 then
		repo = args.args
	end

	local cmd = "cd " .. repo .. " && "
	cmd = cmd .. "gh issue list -L 100 --json number,title,updatedAt -s all "
	cmd = cmd .. "--search 'sort:updated-asc -label:status/5-frozen-due-to-age updated:>=" .. gh.get_current_date() .. "'"
	local handle = io.popen(cmd)
	if handle == nil then
		return
	end

	local list = handle:read("*a")
	handle:close()

	vim.api.nvim_put({ "|Issues|UpdatedAt|Title|Desc|", "|------|---------|-----|----|" }, "l", true, true)
	gh.parse_and_put(list)
end

vim.api.nvim_create_user_command("GhIssues", gh.input_daily_issues, { nargs = "?" })
-- }}}
-- Input daily PRs {{{
function gh.input_daily_prs(args)
	local repo = os.getenv("HOME") .. "/go/src/github.com/traefik/traefik"
	if args.args:len() > 0 then
		repo = args.args
	end

	local cmd = "cd " .. repo .. " && "
	cmd = cmd .. "gh pr list -L 100 --json number,title,updatedAt -s all "
	cmd = cmd .. "--search 'sort:updated-asc -label:status/5-frozen-due-to-age updated:>=" .. gh.get_current_date() .. "'"
	local handle = io.popen(cmd)
	if handle == nil then
		return
	end

	local list = handle:read("*a")
	handle:close()

	vim.api.nvim_put({ "| PR   |UpdatedAt|Title|Desc|", "|------|---------|-----|----|" }, "l", true, true)
	gh.parse_and_put(list)
end

vim.api.nvim_create_user_command("GhPulls", gh.input_daily_prs, { nargs = "?" })
-- }}}
M.gh = gh
-- }}}
--
-- Update nvim components {{{
function Update()
	vim.api.nvim_command(":PackerUpdate")
	vim.api.nvim_command(":TSUpdate")
	print(vim.fn.system({ "go", "install", "golang.org/x/tools/gopls@latest" }))
end

vim.api.nvim_create_user_command("Update", Update, {})
-- }}}

return M
-- vim: foldmethod=marker
