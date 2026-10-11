local config = require('ghlite.config')
local system = require('ghlite.system')

local M = {}

function M.filter_array(arr, condition)
  local result = {}
  for _, v in ipairs(arr) do
    if condition(v) then
      table.insert(result, v)
    end
  end
  return result
end

function M.is_empty(value)
  if value == nil or vim.fn.empty(value) == 1 then
    return true
  end
  return false
end

--- @async
--- @return string
function M.get_git_root()
  local result = system.run_str('git rev-parse --show-toplevel')
  return vim.split(result, '\n')[1]
end

--- @async
--- @return string
function M.get_git_merge_base(baseCommitId, headCommitId)
  local result = system.run_str('git merge-base ' .. baseCommitId .. ' ' .. headCommitId)
  return vim.split(result, '\n')[1]
end

--- @async
--- Ensure the commits needed to compare a pull request exist locally.
--- Fetching is skipped when both commits are already present.
--- @param pr PullRequest
--- @return boolean
function M.ensure_pr_commits(pr)
  local function commit_exists(commit)
    if commit == nil or commit == '' then
      return false
    end
    local result = system.run_result({ 'git', 'cat-file', '-e', commit .. '^{commit}' })
    return result.code == 0
  end

  -- Without baseRefOid (older gh versions), fetch the base branch as well;
  -- the local branch may be stale even when all currently referenced objects exist.
  local base_exists = pr.baseRefOid ~= nil and commit_exists(pr.baseRefOid)
  local head_exists = commit_exists(pr.headRefOid)

  if base_exists and head_exists then
    return true
  end

  system.run_result({
    'git',
    'fetch',
    'origin',
    pr.baseRefName,
    'pull/' .. tostring(pr.number) .. '/head',
  })

  return (pr.baseRefOid == nil or commit_exists(pr.baseRefOid)) and commit_exists(pr.headRefOid)
end

--- @async
--- @return string
function M.get_current_git_branch_name()
  local result = system.run_str('git branch --show-current')
  return vim.split(result, '\n')[1]
end

--- True for a missing value, including JSON null.
--- @param value any
--- @return boolean
function M.is_null(value)
  return value == nil or value == vim.NIL
end

--- @param root string
--- @param filename string absolute path
--- @return string|nil path relative to `root`, nil when the file is outside it
function M.relative_path(root, filename)
  if filename:sub(1, #root + 1) ~= root .. '/' then
    return nil
  end
  return filename:sub(#root + 2)
end

--- @param body string
--- @return boolean
local function is_html_comment(body)
  -- NOTE: naive check if it is HTML comment
  return config.s.html_comments_command ~= false and body:match('<%s*[%w%-]+.-%s*>') ~= nil
end

--- @param body string
--- @param run fun(cmd: string[], opts: table): vim.SystemCompleted
--- @return string
local function render_html(body, run)
  if not is_html_comment(body) then
    return body
  end
  local success, result = pcall(run, config.s.html_comments_command, { stdin = body })
  if success and result.code == 0 then
    return result.stdout
  end
  return body
end

--- Render an HTML comment body (as bots often post) to text with
--- `html_comments_command`; other bodies are returned unchanged.
--- @param body string
--- @return string
function M.html_to_text(body)
  return render_html(body, system.run_sync)
end

--- `html_to_text` without blocking the main loop, for exports rendering many comments.
--- @async
--- @param body string
--- @return string
function M.html_to_text_async(body)
  return render_html(body, system.run_result)
end

--- Ask for a comment in a scratch buffer whose first line says how to send it:
--- `<!-- {instruction} and press {key}[ {purpose}]: -->`.
--- @param title string buffer name; a timestamp is appended
--- @param instruction string e.g. 'Type your comment'
--- @param callback fun(input: string)
--- @param opts? { body?: string, purpose?: string } initial text; what sending does
function M.ask_comment(title, instruction, callback, opts)
  opts = opts or {}
  local key = config.s.keymaps.comment.send_comment
  local prompt = '<!-- '
    .. instruction
    .. ' and press '
    .. key
    .. (opts.purpose and (' ' .. opts.purpose) or '')
    .. ': -->'
  local content = opts.body ~= nil and vim.split(prompt .. '\n' .. opts.body, '\n') or { prompt, '' }
  M.get_comment(
    title .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
    config.s.comment_split,
    prompt,
    content,
    key,
    callback
  )
end

function M.get_comment(buf_name, split_command, prompt, content, key_binding, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, buf_name)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  if split_command then
    vim.api.nvim_command(split_command)
  end
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local function capture_input_and_close()
    local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if prompt ~= nil and input_lines[1] == prompt then
      table.remove(input_lines, 1)
    end
    local input = table.concat(input_lines, '\n')

    vim.cmd('bwipeout')
    callback(input)
  end

  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    key_binding,
    '',
    { noremap = true, silent = true, callback = capture_input_and_close }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'i',
    key_binding,
    '',
    { noremap = true, silent = true, callback = capture_input_and_close }
  )
end

return M
