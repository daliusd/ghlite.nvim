local async = require('async')

local T = MiniTest.new_set()
local expect = MiniTest.expect

local function reload_gh_with_system(system_overrides)
  package.loaded['ghlite.gh'] = nil
  local system = require('ghlite.system')
  local originals = {}
  for key, value in pairs(system_overrides) do
    originals[key] = system[key]
    system[key] = value
  end

  local gh = require('ghlite.gh')

  return gh,
    function()
      for key, value in pairs(originals) do
        system[key] = value
      end
      package.loaded['ghlite.gh'] = nil
    end
end

T['get_current_pr parses gh JSON response'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      expect.equality(cmd, 'gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision')
      return '{"number":42,"headRefName":"feature"}', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_current_pr()
    end)
    :wait(1000)
  restore()

  expect.equality(result.number, 42)
  expect.equality(result.headRefName, 'feature')
end

T['get_current_pr falls back when gh does not know baseRefOid'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return '', 'Unknown JSON field: "baseRefOid"'
      end
      return '{"number":7,"headRefName":"fallback"}', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_current_pr()
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision',
    'gh pr view --json headRefName,headRefOid,number,baseRefName,reviewDecision',
  })
  expect.equality(result.number, 7)
  expect.equality(result.headRefName, 'fallback')
end

T['get_current_pr returns nil for invalid JSON response'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'not-json', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_current_pr()
    end)
    :wait(1000)
  restore()

  expect.equality(result, nil)
end

T['get_changed_files fetches at most 100 files from the pull request API'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return 'owner/repo\n', ''
      end
      return '[{"filename":"lua/example.lua","status":"modified"}]', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_changed_files(42)
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh repo view --json nameWithOwner -q .nameWithOwner',
    'gh api repos/owner/repo/pulls/42/files?per_page=100',
  })
  expect.equality(result, { { filename = 'lua/example.lua', status = 'modified' } })
end

T['get_pr_info requests the commit list alongside the PR fields'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      return '{"number":42,"commits":[{"oid":"abc"}]}', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_pr_info(42)
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh pr view 42 --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits',
  })
  expect.equality(result.commits, { { oid = 'abc' } })
end

T['get_commit fetches a single commit from the commits API'] = function()
  local str_calls = {}
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(str_calls, cmd)
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"sha":"abc123","files":[{"filename":"lua/example.lua"}]}'
    end,
  })

  local result = async
    .run(function()
      return gh.get_commit('abc123')
    end)
    :wait(1000)
  restore()

  expect.equality(str_calls, { 'gh repo view --json nameWithOwner -q .nameWithOwner' })
  expect.equality(api_request, { 'gh', 'api', 'repos/owner/repo/commits/abc123' })
  expect.equality(result.sha, 'abc123')
end

T['get_commit returns nil when the commit is gone'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function()
      return ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_commit('deadbeef')
    end)
    :wait(1000)
  restore()

  expect.equality(result, nil)
end

T['get_commit_checks unwraps the check runs'] = function()
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"total_count":1,"check_runs":[{"name":"build","status":"completed","conclusion":"success"}]}'
    end,
  })

  local result = async
    .run(function()
      return gh.get_commit_checks('abc123')
    end)
    :wait(1000)
  restore()

  expect.equality(api_request, { 'gh', 'api', 'repos/owner/repo/commits/abc123/check-runs' })
  expect.equality(result, { { name = 'build', status = 'completed', conclusion = 'success' } })
end

T['get_commit_checks returns nil when the API call fails'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function()
      return ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_commit_checks('abc123')
    end)
    :wait(1000)
  restore()

  expect.equality(result, nil)
end

T['get_pr_list falls back when gh does not know baseRefOid'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return '', 'Unknown JSON field: "baseRefOid"'
      end
      return '[{"number":5,"headRefName":"fallback"}]', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_pr_list()
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels',
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,labels',
  })
  expect.equality(result, { { number = 5, headRefName = 'fallback' } })
end

T['get_pr_list returns empty list for invalid JSON response'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'not-json', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_pr_list()
    end)
    :wait(1000)
  restore()

  expect.equality(result, {})
end

T['load_comments filters comments without a line before grouping'] = function()
  local calls = {}
  local grouped_input
  local comments_utils = require('ghlite.comments_utils')
  local original_group_comments = comments_utils.group_comments
  comments_utils.group_comments = function(comments)
    grouped_input = comments
    return { grouped = true }
  end

  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return 'owner/repo\n', ''
      end
      return '[{"id":1,"line":10},{"id":2,"line":null}]', ''
    end,
  })

  local result = async
    .run(function()
      return gh.load_comments(12)
    end)
    :wait(1000)
  restore()
  comments_utils.group_comments = original_group_comments

  expect.equality(calls, {
    'gh repo view --json nameWithOwner -q .nameWithOwner',
    'gh api repos/owner/repo/pulls/12/comments',
  })
  expect.equality(#grouped_input, 1)
  expect.equality(grouped_input[1].id, 1)
  expect.equality(result, { grouped = true })
end

T['load_comments keeps outdated comments that carry original_line but no line'] = function()
  local calls = {}
  local grouped_input
  local comments_utils = require('ghlite.comments_utils')
  local original_group_comments = comments_utils.group_comments
  comments_utils.group_comments = function(comments)
    grouped_input = comments
    return { grouped = true }
  end

  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return 'owner/repo\n', ''
      end
      return '[{"id":1,"line":10},{"id":2,"line":null,"original_line":7}]', ''
    end,
  })

  local result = async
    .run(function()
      return gh.load_comments(12)
    end)
    :wait(1000)
  restore()
  comments_utils.group_comments = original_group_comments

  expect.equality(#grouped_input, 2)
  expect.equality(grouped_input[2].id, 2)
  expect.equality(result, { grouped = true })
end

T['new_comment builds gh api request with start_line for ranges'] = function()
  local str_calls = {}
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(str_calls, cmd)
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"id":123}'
    end,
  })

  local response = async
    .run(function()
      return gh.new_comment({ number = 12, headRefOid = 'abc123' }, 'Body', 'lua/example.lua', 3, 5)
    end)
    :wait(1000)
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
