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

T['relative_path strips the root and rejects files outside it'] = function()
  local utils = require('ghlite.utils')

  expect.equality(utils.relative_path('/repo', '/repo/lua/a.lua'), 'lua/a.lua')
  expect.equality(utils.relative_path('/repo', '/repository/a.lua'), nil)
  expect.equality(utils.relative_path('/repo', '/other/a.lua'), nil)
end

T['ask_comment opens the prompt with the send key and optional body and purpose'] = function()
  local utils = require('ghlite.utils')
  local original = utils.get_comment
  local calls = {}
  utils.get_comment = function(name, split, prompt, content, key, callback)
    table.insert(calls, { name = name, prompt = prompt, content = content, key = key, callback = callback })
  end
  local function noop() end
  utils.ask_comment('Title', 'Type your comment', noop)
  utils.ask_comment('Edit', 'Change it', noop, { body = 'old\nbody', purpose = 'to save it' })
  utils.get_comment = original

  expect.equality(calls[1].name:match('^Title %(.+%)$') ~= nil, true)
  expect.equality(calls[1].prompt, '<!-- Type your comment and press c<CR>: -->')
  expect.equality(calls[1].content, { calls[1].prompt, '' })
  expect.equality(calls[1].key, 'c<CR>')
  expect.equality(calls[1].callback, noop)
  expect.equality(calls[2].prompt, '<!-- Change it and press c<CR> to save it: -->')
  expect.equality(calls[2].content, { calls[2].prompt, 'old', 'body' })
end

return T
