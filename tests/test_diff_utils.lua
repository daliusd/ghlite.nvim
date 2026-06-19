local T = MiniTest.new_set()
local expect = MiniTest.expect

T['construct_mappings maps added and context diff lines to file lines'] = function()
  local diff_utils = require('ghlite.diff_utils')

  local filename_line_to_diff_line, diff_line_to_filename_line = diff_utils.construct_mappings({
    'diff --git a/lua/example.lua b/lua/example.lua',
    '--- a/lua/example.lua',
    '+++ b/lua/example.lua',
    '@@ -10,2 +20,3 @@',
    ' context',
    '-removed',
    '+added',
    ' context2',
  }, '/repo')

  expect.equality(filename_line_to_diff_line, {
    ['/repo/lua/example.lua'] = {
      [20] = 5,
      [21] = 7,
      [22] = 8,
    },
  })
  expect.equality(diff_line_to_filename_line, {
    [5] = { '/repo/lua/example.lua', 20 },
    [6] = { '/repo/lua/example.lua', 21 },
    [7] = { '/repo/lua/example.lua', 21 },
    [8] = { '/repo/lua/example.lua', 22 },
  })
end

T['construct_mappings supports multiple files'] = function()
  local diff_utils = require('ghlite.diff_utils')

  local filename_line_to_diff_line, diff_line_to_filename_line = diff_utils.construct_mappings({
    'diff --git a/a.lua b/a.lua',
    '--- a/a.lua',
    '+++ b/a.lua',
    '@@ -1 +1 @@',
    '+a',
    'diff --git a/b.lua b/b.lua',
    '--- a/b.lua',
    '+++ b/b.lua',
    '@@ -4 +8 @@',
    '+b',
  }, '/repo')

  expect.equality(filename_line_to_diff_line['/repo/a.lua'][1], 5)
  expect.equality(filename_line_to_diff_line['/repo/b.lua'][8], 10)
  expect.equality(diff_line_to_filename_line[5], { '/repo/a.lua', 1 })
  expect.equality(diff_line_to_filename_line[10], { '/repo/b.lua', 8 })
end

T['get_diff_tool honors explicit config and auto-detects installed tools'] = function()
  local diff_utils = require('ghlite.diff_utils')

  expect.equality(
    diff_utils.get_diff_tool('diffview', function()
      return false
    end),
    'diffview'
  )
  expect.equality(
    diff_utils.get_diff_tool('codediff', function()
      return false
    end),
    'codediff'
  )
  expect.equality(
    diff_utils.get_diff_tool('auto', function(cmd)
      return cmd == 'DiffviewOpen'
    end),
    'diffview'
  )
  expect.equality(
    diff_utils.get_diff_tool('auto', function(cmd)
      return cmd == 'CodeDiff'
    end),
    'codediff'
  )
  expect.equality(
    diff_utils.get_diff_tool('auto', function()
      return false
    end),
    nil
  )
end

return T
