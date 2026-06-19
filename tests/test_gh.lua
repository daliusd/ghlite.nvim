local T = MiniTest.new_set()
local expect = MiniTest.expect

local function reload_gh_with_utils(utils_overrides)
  package.loaded['ghlite.gh'] = nil
  local utils = require('ghlite.utils')
  local originals = {}
  for key, value in pairs(utils_overrides) do
    originals[key] = utils[key]
    utils[key] = value
  end

  local gh = require('ghlite.gh')

  return gh,
    function()
      for key, value in pairs(originals) do
        utils[key] = value
      end
      package.loaded['ghlite.gh'] = nil
    end
end

T['get_current_pr parses gh JSON response'] = function()
  local gh, restore = reload_gh_with_utils({
    system_str_cb = function(cmd, cb)
      expect.equality(cmd, 'gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision')
      cb('{"number":42,"headRefName":"feature"}', '')
    end,
  })

  local result
  gh.get_current_pr(function(pr)
    result = pr
  end)
  restore()

  expect.equality(result.number, 42)
  expect.equality(result.headRefName, 'feature')
end

T['get_current_pr falls back when gh does not know baseRefOid'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_utils({
    system_str_cb = function(cmd, cb)
      table.insert(calls, cmd)
      if #calls == 1 then
        cb('', 'Unknown JSON field: "baseRefOid"')
      else
        cb('{"number":7,"headRefName":"fallback"}', '')
      end
    end,
  })

  local result
  gh.get_current_pr(function(pr)
    result = pr
  end)
  restore()

  expect.equality(calls, {
    'gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision',
    'gh pr view --json headRefName,headRefOid,number,baseRefName,reviewDecision',
  })
  expect.equality(result.number, 7)
  expect.equality(result.headRefName, 'fallback')
end

T['new_comment builds gh api request with start_line for ranges'] = function()
  local str_calls = {}
  local api_request
  local gh, restore = reload_gh_with_utils({
    system_str_cb = function(cmd, cb)
      table.insert(str_calls, cmd)
      cb('owner/repo\n', '')
    end,
    system_cb = function(cmd, cb)
      api_request = cmd
      cb('{"id":123}')
    end,
  })

  local response
  gh.new_comment({ number = 12, headRefOid = 'abc123' }, 'Body', 'lua/example.lua', 3, 5, function(resp)
    response = resp
  end)
  restore()

  expect.equality(str_calls, { 'gh repo view --json nameWithOwner -q .nameWithOwner' })
  expect.equality(api_request, {
    'gh',
    'api',
    '--method',
    'POST',
    'repos/owner/repo/pulls/12/comments',
    '-f',
    'body=Body',
    '-f',
    'commit_id=abc123',
    '-f',
    'path=lua/example.lua',
    '-F',
    'line=5',
    '-f',
    'side=RIGHT',
    '-F',
    'start_line=3',
  })
  expect.equality(response.id, 123)
end

return T
