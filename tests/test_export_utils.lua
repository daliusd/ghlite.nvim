local T = MiniTest.new_set()
local expect = MiniTest.expect

local export_utils = require('ghlite.export_utils')

local function identity(body)
  return body
end

T['format_location renders single lines, ranges and whole files'] = function()
  expect.equality(export_utils.format_location('a.lua', nil, 4), '`a.lua:4`')
  expect.equality(export_utils.format_location('a.lua', 4, 4), '`a.lua:4`')
  expect.equality(export_utils.format_location('a.lua', 2, 4), '`a.lua:2-4`')
  expect.equality(export_utils.format_location('a.lua', vim.NIL, 4), '`a.lua:4`')
  expect.equality(export_utils.format_location('a.lua', nil, nil), '`a.lua`')
end

T['collect_threads keeps unresolved threads relative to the git root, sorted'] = function()
  local comments_list = {
    ['/repo/b.lua'] = {
      { line = 1, resolved = false, url = 'u-b', comments = { { user = 'alice', body = 'b1' } } },
    },
    ['/repo/a.lua'] = {
      { line = 9, resolved = false, url = 'u-a9', comments = { { user = 'bob', body = 'a9', diff_hunk = 'h' } } },
      { line = 3, resolved = true, url = 'u-a3', comments = { { user = 'bob', body = 'a3' } } },
      { line = 5, resolved = false, comments = {} },
      { line = 2, resolved = false, url = 'u-a2', comments = { { user = 'bot', body = 'noise' } } },
    },
  }

  local threads = export_utils.collect_threads(comments_list, '/repo', {
    threads = 'unresolved',
    exclude_authors = { 'bot' },
  })

  expect.equality(
    vim.tbl_map(function(thread)
      return thread.path .. ':' .. thread.line
    end, threads),
    { 'a.lua:9', 'b.lua:1' }
  )
  expect.equality(threads[1].diff_hunk, 'h')
  expect.equality(threads[1].comments, { { author = 'bob', body = 'a9', pending = false } })

  local all = export_utils.collect_threads(comments_list, '/repo', { threads = 'all' })
  expect.equality(#all, 4)
  expect.equality(export_utils.collect_threads(comments_list, '/repo', { threads = false }), {})
end

T['collect_notes drops empty bodies and excluded authors'] = function()
  local notes = export_utils.collect_notes({
    { author = { login = 'alice' }, state = 'CHANGES_REQUESTED', body = 'Add tests\r\n' },
    { author = { login = 'bob' }, state = 'APPROVED', body = '' },
    { author = { login = 'bot' }, body = 'coverage' },
  }, { 'bot' }, identity)

  expect.equality(notes, { { author = 'alice', state = 'CHANGES_REQUESTED', body = 'Add tests' } })
end

T['render produces the agent markdown layout'] = function()
  local markdown = export_utils.render({
    pr = { number = 34, title = 'Add export', url = 'https://github.test/pr/34', head = 'a1b2c3d4e5' },
    reviews = { { author = 'alice', state = 'CHANGES_REQUESTED', body = 'Please add tests.' } },
    pr_comments = { { author = 'carol', body = 'Line one\nLine two' } },
    threads = {
      {
        path = 'lua/a.lua',
        line = 12,
        start_line = 10,
        outdated = false,
        resolved = false,
        url = 'https://github.test/c/1',
        diff_hunk = '@@ -1 +1 @@\n+x',
        comments = {
          { author = 'alice', body = 'Simplify this.\nIt is long.', pending = false },
          { author = 'bob', body = 'Agree.', pending = true },
        },
      },
      {
        path = 'lua/b.lua',
        line = 3,
        outdated = true,
        resolved = false,
        comments = { { author = 'dave', body = 'Why?', pending = false } },
      },
    },
  }, { intro = 'Please address them.', comment_hunk = true })

  expect.equality(
    markdown,
    table.concat({
      'Please address them.',
      '',
      'Reviewing pull request #34: Add export',
      'URL: https://github.test/pr/34',
      'Head: a1b2c3d',
      '',
      '## Reviews',
      '',
      '- @alice (CHANGES_REQUESTED) - Please add tests.',
      '',
      '## PR comments',
      '',
      '- @carol - Line one',
      '  Line two',
      '',
      '## Review threads',
      '',
      '1. `lua/a.lua:10-12` @alice - Simplify this.',
      '   It is long.',
      '   <https://github.test/c/1>',
      '   - @bob (pending) - Agree.',
      '   ```diff',
      '   @@ -1 +1 @@',
      '   +x',
      '   ```',
      '2. `lua/b.lua:3` (outdated) @dave - Why?',
      '',
    }, '\n')
  )
end

T['render widens the hunk fence past backticks in the hunk'] = function()
  local markdown = export_utils.render({
    reviews = {},
    pr_comments = {},
    threads = {
      {
        path = 'README.md',
        line = 1,
        outdated = false,
        resolved = false,
        diff_hunk = '+```lua',
        comments = { { author = 'a', body = 'b', pending = false } },
      },
    },
  }, { intro = '', comment_hunk = true })

  expect.equality(markdown:find('   ````diff\n   +```lua\n   ````', 1, true) ~= nil, true)
end

T['render keeps only the hunk lines leading up to the commented line'] = function()
  local hunk = { '@@ -1,8 +1,8 @@' }
  for i = 1, 8 do
    table.insert(hunk, ' line ' .. i)
  end
  local markdown = export_utils.render({
    drafts = {},
    reviews = {},
    pr_comments = {},
    threads = {
      {
        path = 'a.lua',
        line = 8,
        outdated = false,
        resolved = false,
        diff_hunk = table.concat(hunk, '\n'),
        comments = { { author = 'a', body = 'b', pending = false } },
      },
    },
  }, { intro = '', comment_hunk = true })

  expect.equality(markdown:find('@@', 1, true), nil)
  expect.equality(markdown:find(' line 2', 1, true), nil)
  expect.equality(markdown:find('   ```diff\n    line 3\n', 1, true) ~= nil, true)
  expect.equality(markdown:find(' line 8\n   ```', 1, true) ~= nil, true)
end

T['is_empty reports exports without any comments'] = function()
  expect.equality(export_utils.is_empty({ pr = { number = 1 }, reviews = {}, pr_comments = {}, threads = {} }), true)
  expect.equality(
    export_utils.is_empty({ reviews = {}, pr_comments = { { author = 'a', body = 'b' } }, threads = {} }),
    false
  )
end

return T
