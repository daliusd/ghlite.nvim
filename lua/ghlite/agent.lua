-- Agent review sessions: draft comments kept on disk instead of GitHub, exported
-- as markdown for a coding agent when the session is submitted.

local config = require('ghlite.config')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local system = require('ghlite.system')

require('ghlite.types')

local M = {}

--- Directory holding one session file per repository.
M.dir = vim.fn.stdpath('data') .. '/ghlite/agent'

--- Sessions read from disk, keyed by git root, with the modification time of the file
--- they were read from so that changes made by another Neovim are picked up.
--- @type table<string, { mtime: string|nil, session: AgentSession|false }>
local cache = {}

--- @type table<string, string|false> working directory -> its git root
local roots = {}

--- Git root of the working directory. Agent sessions do not need a PR, so this avoids
--- `git rev-parse`; it is cached per directory as it runs on every BufEnter.
--- @return string|nil
function M.root()
  local cwd = vim.uv.cwd() or '.'
  if roots[cwd] == nil then
    roots[cwd] = vim.fs.root(cwd, '.git') or false
  end
  return roots[cwd] or nil
end

--- @param root string
--- @return string
function M.session_file(root)
  return M.dir .. '/' .. root:gsub('[/\\:]', '%%') .. '.json'
end

--- @param path string
--- @return string|nil
local function file_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and string.format('%d.%d', stat.mtime.sec, stat.mtime.nsec) or nil
end

--- @param root string
--- @return AgentSession|nil session
--- @return boolean|nil invalid true when the file exists but cannot be read as a session
local function read_session(root)
  local file = io.open(M.session_file(root), 'r')
  if file == nil then
    return nil
  end
  local content = file:read('*a')
  file:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= 'table' or type(decoded.drafts) ~= 'table' then
    return nil, true
  end
  decoded.root = root
  decoded.next_id = tonumber(decoded.next_id) or (#decoded.drafts + 1)
  return decoded
end

--- `vim.fn.mkdir(dir, 'p')` for async tasks, which run outside the main loop.
--- @param dir string
local function mkdir_p(dir)
  if vim.uv.fs_stat(dir) then
    return
  end
  local parent = vim.fs.dirname(dir)
  if parent ~= nil and parent ~= dir then
    mkdir_p(parent)
  end
  vim.uv.fs_mkdir(dir, 448)
end

--- Write through a temporary file and rename it into place, so a crash mid-write never
--- leaves a truncated session behind.
--- @param session AgentSession
local function write_session(session)
  mkdir_p(M.dir)
  local path = M.session_file(session.root)
  local tmp_path = string.format('%s.%d.tmp', path, vim.uv.os_getpid())
  local file = assert(io.open(tmp_path, 'w'))
  file:write(vim.json.encode({ next_id = session.next_id, drafts = session.drafts }))
  file:close()
  assert(vim.uv.fs_rename(tmp_path, path))
  cache[session.root] = { mtime = file_mtime(path), session = session }
end

--- How long a lock may be held before it counts as left behind by a crashed Neovim.
M.stale_lock_seconds = 5

--- Run `fn` holding the session's lock file, so the read-modify-write cycles of several
--- Neovim instances cannot interleave and drop each other's drafts.
--- @param root string
--- @param fn fun(): ...
--- @return ... what `fn` returns
local function with_lock(root, fn)
  mkdir_p(M.dir)
  local lock_path = M.session_file(root) .. '.lock'
  local fd
  -- Changes take milliseconds, so waiting up to a second covers any live holder.
  for _ = 1, 100 do
    fd = vim.uv.fs_open(lock_path, 'wx', 384)
    if fd ~= nil then
      break
    end
    local stat = vim.uv.fs_stat(lock_path)
    if stat ~= nil and os.time() - stat.mtime.sec > M.stale_lock_seconds then
      os.remove(lock_path)
    else
      vim.uv.sleep(10)
    end
  end
  if fd ~= nil then
    vim.uv.fs_close(fd)
  end

  local results = { pcall(fn) }
  if fd ~= nil then
    os.remove(lock_path)
  end
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2, table.maxn(results))
end

--- The active session of `root`, re-read from disk whenever the file changed.
--- @param root string|nil
--- @return AgentSession|nil
function M.get(root)
  if root == nil then
    return nil
  end
  local mtime = file_mtime(M.session_file(root))
  local cached = cache[root]
  if cached == nil or cached.mtime ~= mtime then
    cached = { mtime = mtime, session = mtime ~= nil and read_session(root) or false }
    cache[root] = cached
  end
  return cached.session or nil
end

--- @param root string
--- @return AgentSession session
--- @return boolean created false when a session was already active
function M.start(root)
  state.review_target = 'agent'
  return with_lock(root, function()
    local path = M.session_file(root)
    local session, invalid = read_session(root)
    if session ~= nil then
      cache[root] = { mtime = file_mtime(path), session = session }
      return session, false
    end
    if invalid then
      -- Keep an unreadable session around instead of overwriting the drafts it holds.
      os.rename(path, path .. '.bak')
    end
    session = { root = root, next_id = 1, drafts = {} }
    write_session(session)
    return session, true
  end)
end

--- End the session and drop its drafts.
--- @param root string
function M.discard(root)
  with_lock(root, function()
    os.remove(M.session_file(root))
  end)
  cache[root] = { mtime = nil, session = false }
  if state.review_target == 'agent' then
    state.review_target = nil
  end
end

--- Whether new comments go to the agent session: one is active, and no GitHub review
--- started after it is still pending on the selected PR. Checking the PR rather than
--- trusting `review_target` alone keeps comments local after switching to a PR without
--- a pending review, or after the GitHub review was submitted elsewhere, where they
--- would otherwise be published immediately.
--- @async
--- @param root string|nil
--- @return boolean
function M.is_target(root)
  if M.get(root) == nil then
    return false
  end
  if state.review_target ~= 'github' then
    return true
  end
  local selected_pr = pr_utils.get_selected_pr(true)
  return selected_pr == nil or pr_utils.active_pending_review(selected_pr.number) == nil
end

--- Apply `change` to the latest version of the session on disk and save it, so drafts
--- another Neovim added in the meantime are kept.
--- @param root string
--- @param change fun(session: AgentSession): any
--- @return any|nil result of `change`, nil when the session is gone
local function update_session(root, change)
  return with_lock(root, function()
    -- Read past the cache: a change made within the same timestamp tick is invisible to it.
    local session = read_session(root)
    if session == nil then
      cache[root] = { mtime = file_mtime(M.session_file(root)), session = false }
      return nil
    end
    local result = change(session)
    write_session(session)
    return result
  end)
end

--- @param root string
--- @param path string relative to the git root
--- @param start_line number
--- @param line number
--- @param body string
--- @return AgentDraft|nil draft nil when the session was ended meanwhile
function M.add_draft(root, path, start_line, line, body)
  return update_session(root, function(session)
    --- @type AgentDraft
    local draft = {
      id = session.next_id,
      path = path,
      start_line = start_line,
      line = line,
      body = body,
      created_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    session.next_id = session.next_id + 1
    table.insert(session.drafts, draft)
    return draft
  end)
end

--- @param root string
--- @param id number
--- @param body string
--- @return boolean updated false when the draft or session is gone
function M.update_draft(root, id, body)
  return update_session(root, function(session)
    for _, draft in ipairs(session.drafts) do
      if draft.id == id then
        draft.body = body
        return true
      end
    end
    return false
  end) == true
end

--- @param root string
--- @param id number
function M.delete_draft(root, id)
  update_session(root, function(session)
    session.drafts = vim.tbl_filter(function(draft)
      return draft.id ~= id
    end, session.drafts)
  end)
end

--- Store new lines for drafts whose code moved.
--- @param root string
--- @param moves table<number, { start_line: number, line: number }> draft id -> lines
function M.move_drafts(root, moves)
  update_session(root, function(session)
    for _, draft in ipairs(session.drafts) do
      local move = moves[draft.id]
      if move ~= nil then
        draft.start_line, draft.line = move.start_line, move.line
      end
    end
  end)
end

--- @param session AgentSession
--- @param filename string absolute path
--- @return string|nil path relative to the session root, nil outside it
function M.relative_path(session, filename)
  if filename:sub(1, #session.root + 1) ~= session.root .. '/' then
    return nil
  end
  return filename:sub(#session.root + 2)
end

--- @param draft AgentDraft
--- @return string
function M.format_draft(draft)
  local range = ''
  if draft.start_line ~= draft.line then
    range = string.format(' on lines %d to %d', draft.start_line, draft.line)
  end
  return string.format('🤖 Agent draft%s:\n%s', range, draft.body)
end

--- Refs tried, in order, when `agent.base` is not set.
local default_bases = { 'origin/HEAD', 'origin/main', 'origin/master', 'main', 'master' }

--- What local changes are compared against when no PR is selected: the merge base of
--- `agent.base` (or the first default branch found) and HEAD. On the base branch itself
--- that is HEAD, so only uncommitted changes are left.
--- @async
--- @return LocalScope|nil nil when the repository has no commits
function M.resolve_scope()
  local bases = config.s.agent.base and { config.s.agent.base } or default_bases
  for _, base in ipairs(bases) do
    local result = system.run_result({ 'git', 'merge-base', base, 'HEAD' })
    if result.code == 0 then
      return { base = base, merge_base = vim.trim(result.stdout) }
    end
  end
  local result = system.run_result({ 'git', 'rev-parse', 'HEAD' })
  if result.code ~= 0 then
    return nil
  end
  return { base = 'HEAD', merge_base = vim.trim(result.stdout) }
end

--- Diff of the working tree against the scope: staged and unstaged changes plus
--- untracked files, which `git diff` alone leaves out.
--- @async
--- @param scope LocalScope
--- @return string
function M.get_local_diff(scope)
  local root = M.root() or '.'
  --- @param args string[]
  --- @return string
  local function git(args)
    return system.run(vim.list_extend({ 'git', '-C', root }, args)) or ''
  end
  -- Explicit prefixes: diff parsing expects `b/` even with diff.noprefix configured.
  local function diff_command(...)
    return vim.list_extend({ 'diff', '--no-color', '--no-ext-diff', '--src-prefix=a/', '--dst-prefix=b/' }, { ... })
  end

  local diff = git(diff_command(scope.merge_base))
  for path in git({ 'ls-files', '--others', '--exclude-standard', '-z' }):gmatch('[^%z]+') do
    diff = diff .. git(diff_command('--no-index', '--', '/dev/null', path))
  end
  return diff
end

--- Forget cached sessions and roots; for tests.
function M.reset_cache()
  cache = {}
  roots = {}
end

return M
