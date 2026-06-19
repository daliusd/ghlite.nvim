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
  })

  expect.equality(comment, {
    id = 11,
    url = 'https://github.test/comment/11',
    path = 'lua/example.lua',
    line = 7,
    start_line = 5,
    user = 'reviewer',
    body = 'Looks good',
    updated_at = '2026-06-19T10:00:00Z',
    diff_hunk = '@@ -1 +1 @@',
  })
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

T['group_comments groups replies under the root comment and keys by full path'] = function()
  local utils = require('ghlite.utils')
  local original_get_git_root = utils.get_git_root
  utils.get_git_root = function(cb)
    cb('/repo')
  end

  local comments_utils = require('ghlite.comments_utils')
  local result

  comments_utils.group_comments({
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
  }, function(grouped)
    result = grouped
  end)

  utils.get_git_root = original_get_git_root

  expect.equality(vim.tbl_keys(result), { '/repo/lua/example.lua' })
  expect.equality(#result['/repo/lua/example.lua'], 1)
  expect.equality(result['/repo/lua/example.lua'][1].id, 1)
  expect.equality(result['/repo/lua/example.lua'][1].url, 'https://github.test/comment/2')
  expect.equality(#result['/repo/lua/example.lua'][1].comments, 2)
end

return T
