-- Markdown export of review comments for coding agents.
--
-- The layout follows the one tuicr and review.nvim export: an intro line, what was
-- reviewed, then numbered items anchored to `path:line`, so prompts written for those
-- tools work unchanged.

require('ghlite.types')

local M = {}

--- @param value any
--- @return boolean
local function is_null(value)
  return value == nil or value == vim.NIL
end

--- @param body string|nil
--- @return string
local function clean_body(body)
  local text = string.gsub(body or '', '\r', '')
  return vim.trim(text)
end

--- @param path string
--- @param start_line number|nil
--- @param line number|nil
--- @return string
function M.format_location(path, start_line, line)
  if is_null(line) then
    return '`' .. path .. '`'
  end
  if is_null(start_line) or start_line == line then
    return string.format('`%s:%d`', path, line)
  end
  return string.format('`%s:%d-%d`', path, start_line, line)
end

--- Append `text` as a list item: the first line follows `prefix`, later lines are
--- indented under it so multi-line bodies stay inside the item.
--- @param lines string[]
--- @param prefix string
--- @param text string
--- @param indent string
local function add_item(lines, prefix, text, indent)
  local body_lines = vim.split(text, '\n')
  table.insert(lines, prefix .. body_lines[1])
  for i = 2, #body_lines do
    table.insert(lines, body_lines[i] == '' and '' or indent .. body_lines[i])
  end
end

--- A fence longer than any backtick run in `text`, so a hunk containing a fence
--- cannot close the block early.
--- @param text string
--- @return string
local function fence_for(text)
  local longest = 2
  for run in text:gmatch('`+') do
    longest = math.max(longest, #run)
  end
  return string.rep('`', longest + 1)
end

--- GitHub hunks run from the start of the hunk to the commented line; like the web UI,
--- keep only the lines leading up to it.
M.max_hunk_lines = 6

--- @param lines string[]
--- @param hunk string
--- @param indent string
local function add_hunk(lines, hunk, indent)
  local hunk_lines = vim.split(clean_body(hunk), '\n')
  if #hunk_lines == 1 and hunk_lines[1] == '' then
    return
  end
  if #hunk_lines > M.max_hunk_lines + 1 then
    -- The @@ header would no longer match the lines shown, so it goes too.
    hunk_lines = vim.list_slice(hunk_lines, #hunk_lines - M.max_hunk_lines + 1)
  end
  local fence = fence_for(table.concat(hunk_lines, '\n'))
  table.insert(lines, indent .. fence .. 'diff')
  for _, hunk_line in ipairs(hunk_lines) do
    table.insert(lines, indent .. hunk_line)
  end
  table.insert(lines, indent .. fence)
end

--- @param author string
--- @param exclude_authors string[]|nil
--- @return boolean
local function is_excluded(author, exclude_authors)
  return exclude_authors ~= nil and vim.tbl_contains(exclude_authors, author)
end

--- Flatten loaded review threads into export entries, sorted by path and line.
--- @param comments_list table<string, GroupedComment[]> keyed by absolute path
--- @param git_root string
--- @param opts { threads: 'unresolved'|'all'|false, exclude_authors?: string[] }
--- @return ExportThread[]
function M.collect_threads(comments_list, git_root, opts)
  --- @type ExportThread[]
  local threads = {}
  if not opts.threads then
    return threads
  end

  for filename, conversations in pairs(comments_list) do
    local path = filename
    if filename:sub(1, #git_root + 1) == git_root .. '/' then
      path = filename:sub(#git_root + 2)
    end

    for _, conversation in ipairs(conversations) do
      local keep = #conversation.comments > 0
        and (opts.threads == 'all' or not conversation.resolved)
        and not is_excluded(conversation.comments[1].user, opts.exclude_authors)
      if keep then
        table.insert(threads, {
          path = path,
          line = conversation.line,
          start_line = conversation.start_line,
          outdated = conversation.outdated == true,
          resolved = conversation.resolved == true,
          url = conversation.url,
          diff_hunk = conversation.comments[1].diff_hunk,
          comments = vim.tbl_map(function(comment)
            return { author = comment.user, body = comment.body, pending = comment.pending == true }
          end, conversation.comments),
        })
      end
    end
  end

  table.sort(threads, function(a, b)
    if a.path ~= b.path then
      return a.path < b.path
    end
    return (is_null(a.line) and 0 or a.line) < (is_null(b.line) and 0 or b.line)
  end)
  return threads
end

--- Keep PR-level entries (review summaries or conversation comments) that carry a body.
--- @param entries table[]|nil `gh pr view` reviews or comments
--- @param exclude_authors string[]|nil
--- @param to_text fun(body: string): string
--- @return ExportNote[]
function M.collect_notes(entries, exclude_authors, to_text)
  --- @type ExportNote[]
  local notes = {}
  for _, entry in ipairs(entries or {}) do
    local author = entry.author and entry.author.login or 'unknown'
    local body = clean_body(to_text(entry.body or ''))
    if body ~= '' and not is_excluded(author, exclude_authors) then
      table.insert(notes, { author = author, state = entry.state, body = body })
    end
  end
  return notes
end

--- @param export ExportData
--- @return boolean
function M.is_empty(export)
  return clean_body(export.summary) == ''
    and #export.drafts == 0
    and #export.threads == 0
    and #export.reviews == 0
    and #export.pr_comments == 0
end

--- @param drafts AgentDraft[]
--- @return AgentDraft[] sorted copy, by path and line
function M.sort_drafts(drafts)
  local sorted = vim.list_extend({}, drafts)
  table.sort(sorted, function(a, b)
    if a.path ~= b.path then
      return a.path < b.path
    end
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.id < b.id
  end)
  return sorted
end

--- @param export ExportData
--- @param opts { intro: string, comment_hunk: boolean }
--- @return string
function M.render(export, opts)
  local lines = {}

  local function blank()
    if #lines > 0 and lines[#lines] ~= '' then
      table.insert(lines, '')
    end
  end

  -- `false` disables options elsewhere in the config, so accept it here too.
  local intro = type(opts.intro) == 'string' and opts.intro or ''
  if not M.is_empty(export) and intro ~= '' then
    table.insert(lines, intro)
    blank()
  end

  local pr = export.pr
  if pr ~= nil then
    table.insert(lines, string.format('Reviewing pull request #%d: %s', pr.number, pr.title or ''))
    if not is_null(pr.url) then
      table.insert(lines, 'URL: ' .. pr.url)
    end
    if not is_null(pr.head) then
      table.insert(lines, 'Head: ' .. pr.head:sub(1, 7))
    end
    blank()
  end

  local scope = export.scope
  if pr == nil and scope ~= nil then
    table.insert(
      lines,
      string.format(
        'Reviewing local changes against %s (merge base %s), including uncommitted changes and untracked files',
        scope.base,
        scope.merge_base:sub(1, 7)
      )
    )
    blank()
  end

  local summary = clean_body(export.summary)
  if summary ~= '' then
    add_item(lines, 'Summary: ', summary, '')
    blank()
  end

  if #export.drafts > 0 then
    table.insert(lines, '## Comments')
    table.insert(lines, '')
    for i, draft in ipairs(M.sort_drafts(export.drafts)) do
      local marker = string.format('%d. ', i)
      add_item(
        lines,
        marker .. M.format_location(draft.path, draft.start_line, draft.line) .. ' - ',
        clean_body(draft.body),
        string.rep(' ', #marker)
      )
    end
    blank()
  end

  if #export.reviews > 0 then
    table.insert(lines, '## Reviews')
    table.insert(lines, '')
    for _, review in ipairs(export.reviews) do
      local state = review.state and (' (' .. review.state .. ')') or ''
      add_item(lines, string.format('- @%s%s - ', review.author, state), review.body, '  ')
    end
    blank()
  end

  if #export.pr_comments > 0 then
    table.insert(lines, '## PR comments')
    table.insert(lines, '')
    for _, comment in ipairs(export.pr_comments) do
      add_item(lines, string.format('- @%s - ', comment.author), comment.body, '  ')
    end
    blank()
  end

  if #export.threads > 0 then
    table.insert(lines, '## Review threads')
    table.insert(lines, '')
    for i, thread in ipairs(export.threads) do
      local marker = string.format('%d. ', i)
      local indent = string.rep(' ', #marker)
      local flags = {}
      if thread.outdated then
        table.insert(flags, 'outdated')
      end
      if thread.resolved then
        table.insert(flags, 'resolved')
      end
      local location = M.format_location(thread.path, thread.start_line, thread.line)
      if #flags > 0 then
        location = location .. ' (' .. table.concat(flags, ', ') .. ')'
      end

      local first = thread.comments[1]
      add_item(
        lines,
        string.format('%s%s @%s%s - ', marker, location, first.author, first.pending and ' (pending)' or ''),
        clean_body(first.body),
        indent
      )
      if not is_null(thread.url) and thread.url ~= '' then
        table.insert(lines, indent .. '<' .. thread.url .. '>')
      end
      for j = 2, #thread.comments do
        local reply = thread.comments[j]
        add_item(
          lines,
          string.format('%s- @%s%s - ', indent, reply.author, reply.pending and ' (pending)' or ''),
          clean_body(reply.body),
          indent .. '  '
        )
      end
      if opts.comment_hunk and not is_null(thread.diff_hunk) then
        add_hunk(lines, thread.diff_hunk, indent)
      end
    end
    blank()
  end

  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end
  return table.concat(lines, '\n') .. '\n'
end

return M
