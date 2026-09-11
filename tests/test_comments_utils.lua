local T = MiniTest.new_set()
local expect = MiniTest.expect

T['convert_comment maps GitHub API fields to internal comment'] = function()
  local comments_utils = require('ghlite.comments_utils')

  local comment = comments_utils.convert_comment({
    id = 11,
    html_url = 'https://github.test/comment/11',
    path = 'lua/example.lua',
    line = 7,
    start_line = 5,
    user = { login = 'reviewer' },
    body = 'Looks good',
    updated_at = '2026-06-19T10:00:00Z',
    diff_hunk = '@@ -1 +1 @@',
    commit_id = 'head-sha',
    original_commit_id = 'original-sha',
  })

  expect.equality(comment, {
    id = 11,
    url = 'https://github.test/comment/11',
    path = 'lua/example.lua',
    line = 7,
    start_line = 5,
    outdated = false,
    user = 'reviewer',
    body = 'Looks good',
    updated_at = '2026-06-19T10:00:00Z',
    diff_hunk = '@@ -1 +1 @@',
    commit_id = 'head-sha',
    original_commit_id = 'original-sha',
    pending = false,
  })
end

T['convert_comment marks a comment outdated when position is null but original_position remains'] = function()
  local comments_utils = require('ghlite.comments_utils')

  local comment = comments_utils.convert_comment({
    id = 12,
    html_url = 'https://github.test/comment/12',
    path = 'lua/example.lua',
    line = vim.NIL,
    start_line = vim.NIL,
    original_line = 7,
    original_start_line = vim.NIL,
    position = vim.NIL,
    original_position = 3,
    user = { login = 'reviewer' },
    body = 'Stale now',
    updated_at = '2026-06-19T10:00:00Z',
    diff_hunk = '@@ -1 +1 @@',
  })

  expect.equality(comment.outdated, true)
  expect.equality(comment.original_line, 7)
end

T['prepare_content includes range, comments, and diff hunk'] = function()
  local comments_utils = require('ghlite.comments_utils')

  local content = comments_utils.prepare_content({
    {
      user = 'alice',
      updated_at = 'today',
      body = 'First\r\ncomment',
      start_line = 3,
      line = 5,
      diff_hunk = '@@ -3,3 +3,3 @@',
    },
    {
      user = 'bob',
      updated_at = 'later',
      body = 'Reply',
      start_line = vim.NIL,
      line = 5,
      diff_hunk = '@@ ignored @@',
    },
  })

  expect.equality(
    content,
    '📓 Comment on lines 3 to 5\n\n'
      .. '✍️ alice at today:\nFirst\ncomment\n\n'
      .. '✍️ bob at later:\nReply\n\n'
      .. '\n🪓 Diff hunk:\n@@ -3,3 +3,3 @@\n'
  )
end

T['prepare_content keeps resolution status for range comments'] = function()
  local comments_utils = require('ghlite.comments_utils')

  local content = comments_utils.prepare_content({
    {
      user = 'alice',
      updated_at = 'today',
      body = 'Range comment',
      start_line = 3,
      line = 5,
      diff_hunk = '@@ -3,3 +3,3 @@',
    },
  }, { resolved = true, comment_hunk = false })

  expect.equality(content, '✅ Resolved\n\n📓 Comment on lines 3 to 5\n\n✍️ alice at today:\nRange comment\n\n')
end

T['prepare_content can omit diff hunk'] = function()
  local comments_utils = require('ghlite.comments_utils')

  local content = comments_utils.prepare_content({
    {
      user = 'alice',
      updated_at = 'today',
      body = 'First comment',
      start_line = vim.NIL,
      line = 5,
      diff_hunk = '@@ -3,3 +3,3 @@',
    },
  }, { comment_hunk = false })

  expect.equality(content, '✍️ alice at today:\nFirst comment\n\n')
end

T['group_comments groups replies under the root comment and keys by full path'] = function()
  local async = require('async')
  local utils = require('ghlite.utils')
  local original_get_git_root = utils.get_git_root
  utils.get_git_root = function()
    return '/repo'
  end

  local comments_utils = require('ghlite.comments_utils')

  local comments = {
    {
      id = 1,
      html_url = 'https://github.test/comment/1',
      path = 'lua/example.lua',
      line = 10,
      start_line = vim.NIL,
      user = { login = 'alice' },
      body = 'Root',
      updated_at = 'now',
      diff_hunk = '@@ -10 +10 @@',
      original_commit_id = 'original-sha',
    },
    {
      id = 2,
      in_reply_to_id = 1,
      html_url = 'https://github.test/comment/2',
      path = 'lua/example.lua',
      line = 10,
      start_line = vim.NIL,
      user = { login = 'bob' },
      body = 'Reply',
      updated_at = 'later',
      diff_hunk = '@@ -10 +10 @@',
    },
  }

  local result = async
    .run(function()
      return comments_utils.group_comments(comments)
    end)
    :wait(1000)

  utils.get_git_root = original_get_git_root

  expect.equality(vim.tbl_keys(result), { '/repo/lua/example.lua' })
  expect.equality(#result['/repo/lua/example.lua'], 1)
  expect.equality(result['/repo/lua/example.lua'][1].id, 1)
  expect.equality(result['/repo/lua/example.lua'][1].url, 'https://github.test/comment/2')
  expect.equality(#result['/repo/lua/example.lua'][1].comments, 2)
  -- the root comment's commit is what the commit view filters on
  expect.equality(result['/repo/lua/example.lua'][1].original_commit_id, 'original-sha')
end

T['group_comments falls back to original_line for outdated comments'] = function()
  local async = require('async')
  local utils = require('ghlite.utils')
  local original_get_git_root = utils.get_git_root
  utils.get_git_root = function()
    return '/repo'
  end

  local comments_utils = require('ghlite.comments_utils')

  local comments = {
    {
      id = 1,
      html_url = 'https://github.test/comment/1',
      path = 'lua/example.lua',
      line = vim.NIL,
      start_line = vim.NIL,
      original_line = 10,
      original_start_line = vim.NIL,
      position = vim.NIL,
      original_position = 4,
      user = { login = 'alice' },
      body = 'Root',
      updated_at = 'now',
      diff_hunk = '@@ -10 +10 @@',
    },
  }

  local result = async
    .run(function()
      return comments_utils.group_comments(comments)
    end)
    :wait(1000)

  utils.get_git_root = original_get_git_root

  expect.equality(result['/repo/lua/example.lua'][1].line, 10)
  expect.equality(result['/repo/lua/example.lua'][1].outdated, true)
end

T['line_from_diff_hunk counts the new-file line the hunk ends on'] = function()
  local comments_utils = require('ghlite.comments_utils')

  -- Real hunk from a pending comment placed on line 8: deletions do not advance the
  -- new-file line, additions and context lines do.
  local hunk = table.concat({
    '@@ -2,6 +2,18 @@ local M = {}',
    ' ',
    ' function M.add(a, b)',
    '   return a + b',
    '- end',
    '+end',
    '+',
    '+function M.sub(a, b)',
    '+  return a - b',
  }, '\n')

  expect.equality(comments_utils.line_from_diff_hunk(hunk), 8)
  expect.equality(comments_utils.line_from_diff_hunk('@@ -1 +1 @@\n+one'), 1)
  expect.equality(comments_utils.line_from_diff_hunk('not a hunk'), nil)
  expect.equality(comments_utils.line_from_diff_hunk(nil), nil)
end

return T
