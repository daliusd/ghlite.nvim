local async = require('async')

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

T['get_git helpers return the first output line'] = function()
  local utils = require('ghlite.utils')
  local system = require('ghlite.system')
  local original_run_str = system.run_str
  local calls = {}
  system.run_str = function(cmd)
    table.insert(calls, cmd)
    return 'first-line\nsecond-line\n', ''
  end

  local git_root, merge_base, branch = async
    .run(function()
      return utils.get_git_root(), utils.get_git_merge_base('base', 'head'), utils.get_current_git_branch_name()
    end)
    :wait(1000)

  system.run_str = original_run_str

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
