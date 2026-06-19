local T = MiniTest.new_set()
local expect = MiniTest.expect

T['filter_array keeps values matching condition without mutating input'] = function()
  local utils = require('ghlite.utils')
  local input = { 1, 2, 3, 4 }

  local result = utils.filter_array(input, function(value)
    return value % 2 == 0
  end)

  expect.equality(result, { 2, 4 })
  expect.equality(input, { 1, 2, 3, 4 })
end

T['is_empty treats nil, empty strings, and empty tables as empty'] = function()
  local utils = require('ghlite.utils')

  expect.equality(utils.is_empty(nil), true)
  expect.equality(utils.is_empty(''), true)
  expect.equality(utils.is_empty({}), true)
end

T['is_empty treats non-empty values as not empty'] = function()
  local utils = require('ghlite.utils')

  expect.equality(utils.is_empty('x'), false)
  expect.equality(utils.is_empty({ 'x' }), false)
  expect.equality(utils.is_empty(1), false)
end

T['get_git helpers pass the first output line to callback'] = function()
  local utils = require('ghlite.utils')
  local original_system_str_cb = utils.system_str_cb
  local calls = {}
  utils.system_str_cb = function(cmd, cb)
    table.insert(calls, cmd)
    cb('first-line\nsecond-line\n')
  end

  local git_root
  local merge_base
  local branch
  utils.get_git_root(function(result)
    git_root = result
  end)
  utils.get_git_merge_base('base', 'head', function(result)
    merge_base = result
  end)
  utils.get_current_git_branch_name(function(result)
    branch = result
  end)

  utils.system_str_cb = original_system_str_cb

  expect.equality(calls, {
    'git rev-parse --show-toplevel',
    'git merge-base base head',
    'git branch --show-current',
  })
  expect.equality(git_root, 'first-line')
  expect.equality(merge_base, 'first-line')
  expect.equality(branch, 'first-line')
end

return T
