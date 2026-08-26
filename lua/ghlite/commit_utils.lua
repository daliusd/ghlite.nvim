local config = require('ghlite.config')
local state = require('ghlite.state')
local utils = require('ghlite.utils')

require('ghlite.types')

local M = {}

--- @param value any
--- @return string|nil
local function nil_if_empty(value)
  if value == nil or value == vim.NIL or value == '' then
    return nil
  end
  return value
end

M.nil_if_empty = nil_if_empty

--- Start a section, keeping exactly one blank line above its heading.
--- @param lines string[]
--- @param heading string
local function open_section(lines, heading)
  if #lines > 0 and lines[#lines] ~= '' then
    table.insert(lines, '')
  end
  table.insert(lines, heading)
  table.insert(lines, '')
end

--- @param sha string|nil
--- @return string
function M.short_sha(sha)
  if sha == nil or sha == vim.NIL then
    return 'unknown'
  end
  return sha:sub(1, 7)
end

--- True for paths that `construct_mappings` derived from a `/dev/null` diff
--- header, which have no counterpart on disk.
--- @param filename string|nil
--- @return boolean
function M.is_dev_null(filename)
  return filename ~= nil and filename:match('/dev/null$') ~= nil
end

local file_statuses = {
  added = 'A',
  changed = 'M',
  copied = 'C',
  modified = 'M',
  removed = 'D',
  renamed = 'R',
}

--- @param person table|nil git author/committer object
--- @param account table|nil linked GitHub account
--- @return string
function M.format_person(person, account)
  if person == nil or person == vim.NIL then
    return 'unknown'
  end

  local name = nil_if_empty(person.name) or 'unknown'
  local login = account ~= nil and account ~= vim.NIL and nil_if_empty(account.login) or nil
  if login ~= nil and login ~= name then
    name = string.format('%s (%s)', name, login)
  end

  local date = nil_if_empty(person.date)
  if date == nil then
    return name
  end
  return string.format('%s at %s', name, date)
end

--- @param check_runs table[]|nil
--- @return string[]
function M.format_checks(check_runs)
  if check_runs == nil or #check_runs == 0 then
    return {}
  end

  local passed, failed, pending = 0, 0, 0
  local problems = {}

  for _, check in ipairs(check_runs) do
    if check.status ~= 'completed' then
      pending = pending + 1
      table.insert(problems, string.format('    ⏳ %s (%s)', check.name, check.status))
    elseif check.conclusion == 'success' or check.conclusion == 'neutral' or check.conclusion == 'skipped' then
      passed = passed + 1
    else
      failed = failed + 1
      table.insert(problems, string.format('    ✗ %s (%s)', check.name, check.conclusion or 'unknown'))
    end
  end

  local summary = {}
  if passed > 0 then
    table.insert(summary, string.format('%d passed', passed))
  end
  if failed > 0 then
    table.insert(summary, string.format('%d failed', failed))
  end
  if pending > 0 then
    table.insert(summary, string.format('%d pending', pending))
  end

  local lines = { 'Checks: ' .. table.concat(summary, ', ') }
  for _, problem in ipairs(problems) do
    table.insert(lines, problem)
  end
  return lines
end

--- Render the heterogeneous `statusCheckRollup` returned by `gh pr view`.
--- @param checks StatusCheckRollup[]|nil
--- @return string[]
function M.format_pr_checks(checks)
  if checks == nil or #checks == 0 then
    return {}
  end

  local entries = {}
  for _, check in ipairs(checks) do
    local name = check.name or check.context or 'unknown check'
    local raw_state
    local outcome

    if check.context ~= nil then
      raw_state = check.state or 'unknown'
      local state = raw_state:lower()
      if state == 'success' then
        outcome = 'passed'
      elseif state == 'pending' or state == 'expected' then
        outcome = 'pending'
      else
        outcome = 'failed'
      end
    elseif (check.status or ''):lower() ~= 'completed' then
      raw_state = check.status or 'unknown'
      outcome = 'pending'
    else
      raw_state = check.conclusion or 'unknown'
      local conclusion = raw_state:lower()
      if conclusion == 'success' or conclusion == 'neutral' or conclusion == 'skipped' then
        outcome = 'passed'
      else
        outcome = 'failed'
      end
    end

    local detail = check.workflowName or check.description
    if detail ~= nil and detail ~= '' then
      name = string.format('%s — %s', name, detail)
    end
    table.insert(entries, { name = name, state = raw_state, outcome = outcome })
  end

  table.sort(entries, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  local icons = { passed = '✓', failed = '✗', pending = '⏳' }
  local lines = { '', '## Checks', '' }
  for _, entry in ipairs(entries) do
    table.insert(lines, string.format('    %s %s (%s)', icons[entry.outcome], entry.name, entry.state))
  end
  return lines
end

--- @param verification table|nil
--- @return string|nil
function M.format_verification(verification)
  if verification == nil or verification == vim.NIL then
    return nil
  end
  if verification.verified then
    return 'Signature: verified'
  end
  if verification.reason ~= nil and verification.reason ~= 'unsigned' then
    return 'Signature: unverified (' .. verification.reason .. ')'
  end
  return nil
end

--- @param has_commit_list boolean
--- @return string
function M.format_commit_keymaps(has_commit_list)
  local keymaps = {
    { config.s.keymaps.commit.open_file, 'open file' },
    { config.s.keymaps.commit.open_file_split, 'open in split' },
    { config.s.keymaps.commit.open_file_vsplit, 'open in vsplit' },
    { config.s.keymaps.commit.diff, 'open commit diff' },
    { config.s.keymaps.commit.yank_sha, 'yank SHA' },
    { config.s.keymaps.commit.open_in_browser, 'open in browser' },
    { config.s.keymaps.commit.refresh, 'refresh' },
    { config.s.keymaps.commit.close, 'close' },
  }

  if has_commit_list then
    table.insert(keymaps, 4, { config.s.keymaps.commit.next_commit, 'next commit' })
    table.insert(keymaps, 5, { config.s.keymaps.commit.prev_commit, 'previous commit' })
  end

  local hints = {}
  for _, keymap in ipairs(keymaps) do
    if not utils.is_empty(keymap[1]) then
      table.insert(hints, keymap[1] .. ': ' .. keymap[2])
    end
  end

  return table.concat(hints, '   ')
end

--- Review comments left on this commit, grouped by file. Returns the section
--- body only; the caller adds the heading when there is anything to show.
--- @param sha string
--- @return string[]
function M.format_commit_review_comments(sha)
  local matches = {}

  for filename, comment_groups in pairs(state.comments_list or {}) do
    for _, comment_group in ipairs(comment_groups) do
      -- NOTE: only `original_commit_id` identifies the commit a comment was
      -- written against. `commit_id` is the latest commit the comment still
      -- applies to, which is the PR head for every non-outdated comment.
      if comment_group.original_commit_id == sha and #comment_group.comments > 0 then
        table.insert(matches, { filename = filename, group = comment_group })
      end
    end
  end

  if #matches == 0 then
    return {}
  end

  table.sort(matches, function(a, b)
    if a.filename == b.filename then
      return a.group.line < b.group.line
    end
    return a.filename < b.filename
  end)

  local lines = {}
  for _, match in ipairs(matches) do
    local relative_filename = match.filename:match('^.*/(.*)$') or match.filename
    table.insert(lines, string.format('### %s:%d', relative_filename, match.group.line))
    table.insert(lines, '')

    for idx, comment in ipairs(match.group.comments) do
      if idx == 1 then
        table.insert(lines, string.format('✍️ %s at %s:', comment.user, comment.updated_at))
      else
        table.insert(lines, string.format('✍️ %s replied at %s:', comment.user, comment.updated_at))
      end
      for _, line in ipairs(vim.split(string.gsub(comment.body, '\r', ''), '\n')) do
        table.insert(lines, line)
      end
      table.insert(lines, '')
    end
  end

  return lines
end

--- Rebuild a unified diff for one file. The commits API returns only the
--- hunks, so the `diff --git`/`---`/`+++` headers have to be synthesized both
--- for diff highlighting and for `diff_utils.construct_mappings`.
--- @param file CommitFile
--- @return string[]
function M.build_file_diff(file)
  local old_path = nil_if_empty(file.previous_filename) or file.filename
  local lines = { string.format('diff --git a/%s b/%s', old_path, file.filename) }

  if file.status == 'added' then
    table.insert(lines, '--- /dev/null')
  else
    table.insert(lines, '--- a/' .. old_path)
  end

  if file.status == 'removed' then
    table.insert(lines, '+++ /dev/null')
  else
    table.insert(lines, '+++ b/' .. file.filename)
  end

  for _, line in ipairs(vim.split(string.gsub(file.patch, '\r', ''), '\n')) do
    table.insert(lines, line)
  end

  return lines
end

--- @param commit CommitDetails
--- @param check_runs table[]|nil
--- @param opts table `pr_number` and `commits` only affect the rendering
--- @return string[] lines
--- @return number[] unmappable_lines lines in the diff section that are not diff content
function M.format_commit_view(commit, check_runs, opts)
  opts = opts or {}

  local message = string.gsub(nil_if_empty(commit.commit.message) or '', '\r', '')
  local message_lines = vim.split(message, '\n')
  local headline = table.remove(message_lines, 1)

  local author = M.format_person(commit.commit.author, commit.author)
  local lines = {
    string.format('%s %s', M.short_sha(commit.sha), headline),
    '',
    'SHA: ' .. commit.sha,
    'Author: ' .. author,
  }

  local committer = M.format_person(commit.commit.committer, commit.committer)
  if committer ~= author then
    table.insert(lines, 'Committer: ' .. committer)
  end

  local parents = {}
  for _, parent in ipairs(commit.parents or {}) do
    table.insert(parents, M.short_sha(parent.sha))
  end
  if #parents > 0 then
    table.insert(lines, 'Parents: ' .. table.concat(parents, ', ') .. (#parents > 1 and ' (merge commit)' or ''))
  end

  if opts.pr_number ~= nil then
    table.insert(lines, string.format('PR: #%d', opts.pr_number))
  end

  local files = commit.files or {}
  local stats = commit.stats or {}
  table.insert(
    lines,
    string.format(
      'Changes: %d file%s changed, +%d -%d',
      #files,
      #files == 1 and '' or 's',
      stats.additions or 0,
      stats.deletions or 0
    )
  )

  local verification = M.format_verification(commit.commit.verification)
  if verification ~= nil then
    table.insert(lines, verification)
  end

  for _, line in ipairs(M.format_checks(check_runs)) do
    table.insert(lines, line)
  end

  local keymap_hints = M.format_commit_keymaps(opts.commits ~= nil and #opts.commits > 1)
  if keymap_hints ~= '' then
    table.insert(lines, '')
    table.insert(lines, keymap_hints)
  end

  if #message_lines > 0 then
    table.insert(lines, '')
    for _, line in ipairs(message_lines) do
      table.insert(lines, line)
    end
  end

  open_section(lines, '## Changed files')

  if #files == 0 then
    table.insert(lines, '    No files changed.')
  end

  local without_patch = {}
  for _, file in ipairs(files) do
    local name = file.filename
    if nil_if_empty(file.previous_filename) ~= nil then
      name = file.previous_filename .. ' → ' .. file.filename
    end
    table.insert(
      lines,
      string.format(
        '    %s %s  +%d -%d',
        file_statuses[file.status] or '?',
        name,
        file.additions or 0,
        file.deletions or 0
      )
    )
    if nil_if_empty(file.patch) == nil then
      table.insert(without_patch, file.filename)
    end
  end

  if #without_patch > 0 then
    table.insert(lines, '')
    table.insert(lines, '    Diff not shown (binary or too large): ' .. table.concat(without_patch, ', '))
  end

  local review_lines = M.format_commit_review_comments(commit.sha)
  if #review_lines > 0 then
    open_section(lines, '## Review comments')
    for _, line in ipairs(review_lines) do
      table.insert(lines, line)
    end
  end

  local diff_lines = {}
  for _, file in ipairs(files) do
    if nil_if_empty(file.patch) ~= nil then
      for _, line in ipairs(M.build_file_diff(file)) do
        table.insert(diff_lines, line)
      end
    end
  end

  local unmappable_lines = {}
  if #diff_lines > 0 then
    open_section(lines, '## Diff')
    -- NOTE: four backticks so a fenced block inside the commit message body
    -- cannot close the diff block early.
    table.insert(lines, '````diff')
    for _, line in ipairs(diff_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, '````')
    -- The closing fence sits after a `+++` header, so drop the file mapping
    -- `construct_mappings` would otherwise assign to it.
    table.insert(unmappable_lines, #lines)
  end

  return lines, unmappable_lines
end

--- @param commit Commit
--- @return string
local function format_commit_author(commit)
  local author = commit.authors and commit.authors[1]
  if author == nil or author == vim.NIL then
    return 'unknown'
  end
  if not utils.is_empty(author.login) then
    return author.login
  end
  if not utils.is_empty(author.name) then
    return author.name
  end
  return 'unknown'
end

--- Commit list rendered inside the PR view.
--- @param commits Commit[]|nil
--- @return string[] lines
--- @return table<number, number> commit index by line offset within `lines`
function M.format_commits(commits)
  local lines = { '', '## Commits', '' }
  local index_by_line = {}

  if commits == nil or #commits == 0 then
    table.insert(lines, '    No commits found.')
    return lines, index_by_line
  end

  for index, commit in ipairs(commits) do
    local headline = commit.messageHeadline or ''
    if #headline > 72 then
      headline = headline:sub(1, 69) .. '...'
    end

    local date = commit.committedDate and commit.committedDate:sub(1, 10) or 'unknown'
    table.insert(
      lines,
      string.format('    %s  %s (%s, %s)', M.short_sha(commit.oid), headline, format_commit_author(commit), date)
    )
    index_by_line[#lines] = index
  end

  return lines, index_by_line
end

return M
