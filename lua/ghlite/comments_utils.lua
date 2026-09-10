local utils = require('ghlite.utils')
require('ghlite.types')

local M = {}

--- @param value any
--- @return boolean
local function is_null(value)
  return value == nil or value == vim.NIL
end

--- @return Comment: extracted gh comment
function M.convert_comment(comment)
  return {
    id = comment.id,
    url = comment.html_url,
    path = comment.path,
    line = comment.line,
    start_line = comment.start_line,
    original_line = comment.original_line,
    original_start_line = comment.original_start_line,
    outdated = is_null(comment.position) and not is_null(comment.original_position),
    user = comment.user.login,
    body = comment.body,
    updated_at = comment.updated_at,
    diff_hunk = comment.diff_hunk,
    commit_id = comment.commit_id,
    original_commit_id = comment.original_commit_id,
  }
end

--- Convert a comment node returned by a pending-review mutation. GraphQL reports
--- neither position nor the lines the comment was placed on, so the caller passes the
--- lines it asked for and the comment is never outdated - it was just created.
--- @param node table GraphQL PullRequestReviewComment node
--- @param start_line number
--- @param line number
--- @return Comment
function M.convert_pending_comment(node, start_line, line)
  return {
    id = node.databaseId,
    url = node.url,
    path = node.path,
    line = line,
    start_line = start_line,
    outdated = false,
    user = node.author and node.author.login or '',
    body = node.body,
    updated_at = node.updatedAt,
    diff_hunk = node.diffHunk or '',
  }
end

--- @param comment Comment
local function format_comment(comment)
  return string.format(
    '✍️ %s at %s:\n%s\n\n',
    comment.user,
    comment.updated_at,
    string.gsub(comment.body, '\r', '')
  )
end

--- @param comments Comment[]
--- @param opts? { comment_hunk?: boolean, resolved?: boolean }
function M.prepare_content(comments, opts)
  opts = opts or {}
  local comment_hunk = opts.comment_hunk
  if comment_hunk == nil then
    comment_hunk = true
  end

  local content = opts.resolved == nil and '' or (opts.resolved and '✅ Resolved\n\n' or '○ Unresolved\n\n')
  local first = comments[1]
  local effective_line = first and (is_null(first.line) and first.original_line or first.line)
  local effective_start_line = first and (is_null(first.start_line) and first.original_start_line or first.start_line)
  if #comments > 0 and not is_null(effective_start_line) and effective_start_line ~= effective_line then
    content = content .. string.format('📓 Comment on lines %d to %d\n\n', effective_start_line, effective_line)
  end

  for _, comment in pairs(comments) do
    content = content .. format_comment(comment)
  end

  if comment_hunk and #comments > 0 then
    content = content .. '\n🪓 Diff hunk:\n' .. comments[1].diff_hunk .. '\n'
  end

  return content
end

--- @async
--- @return table<string, GroupedComment[]>
function M.group_comments(gh_comments, opts, thread_statuses)
  local git_root = utils.get_git_root()

  --- @type table<number, Comment[]>
  local comment_groups = {}
  local base = {}

  for _, comment in pairs(gh_comments) do
    if comment.in_reply_to_id == nil then
      comment_groups[comment.id] = { M.convert_comment(comment) }
      base[comment.id] = comment.id
    else
      table.insert(comment_groups[base[comment.in_reply_to_id]], M.convert_comment(comment))
      base[comment.id] = base[comment.in_reply_to_id]
    end
  end

  --- @type table<string, GroupedComment[]>
  local result = {}
  for _, comments in pairs(comment_groups) do
    --- @type GroupedComment
    local grouped_comments = {
      id = comments[1].id,
      line = is_null(comments[1].line) and comments[1].original_line or comments[1].line,
      start_line = is_null(comments[1].start_line) and comments[1].original_start_line or comments[1].start_line,
      outdated = comments[1].outdated,
      url = comments[#comments].url,
      content = M.prepare_content(comments, opts),
      comments = comments,
      commit_id = comments[1].commit_id,
      original_commit_id = comments[1].original_commit_id,
      resolved = false,
    }
    local thread = thread_statuses and thread_statuses[grouped_comments.id]
    if thread then
      grouped_comments.thread_id = thread.thread_id
      grouped_comments.resolved = thread.resolved
    end
    grouped_comments.content = M.prepare_content(comments, {
      comment_hunk = opts and opts.comment_hunk,
      resolved = grouped_comments.resolved,
    })

    local full_path = git_root .. '/' .. comments[1].path
    if result[full_path] == nil then
      result[full_path] = { grouped_comments }
    else
      table.insert(result[full_path], grouped_comments)
    end
  end

  return result
end

return M
