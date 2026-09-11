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

T['get_current_pr parses gh JSON response and forwards passive lookup mode'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd, silent)
      expect.equality(cmd, 'gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision')
      expect.equality(silent, true)
      return '{"number":42,"headRefName":"feature"}', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_current_pr(true)
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

T['get_pr_info requests commits and the status check rollup'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      return '{"number":42,"commits":[{"oid":"abc"}],"statusCheckRollup":[{"name":"build","status":"completed","conclusion":"success"}]}',
        ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_pr_info(42)
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh pr view 42 --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits,statusCheckRollup',
  })
  expect.equality(result.commits, { { oid = 'abc' } })
  expect.equality(result.statusCheckRollup[1].name, 'build')
end

T['get_pr_info falls back when gh does not know statusCheckRollup'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return '', 'Unknown JSON field: "statusCheckRollup"'
      end
      return '{"number":42}', ''
    end,
  })

  local result = async
    .run(function()
      return gh.get_pr_info(42)
    end)
    :wait(1000)
  restore()

  expect.equality(calls, {
    'gh pr view 42 --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits,statusCheckRollup',
    'gh pr view 42 --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits',
  })
  expect.equality(result.number, 42)
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
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels,statusCheckRollup',
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,labels',
  })
  expect.equality(result, { { number = 5, headRefName = 'fallback' } })
end

T['get_pr_list falls back when gh does not know statusCheckRollup'] = function()
  local calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      table.insert(calls, cmd)
      if #calls == 1 then
        return '', 'Unknown JSON field: "statusCheckRollup"'
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
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels,statusCheckRollup',
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

--- `gh api -i` output: status line, headers, blank line, body.
local function http_response(status, etag, body)
  return table.concat({
    'HTTP/2.0 ' .. status,
    'Content-Type: application/json',
    'ETag: ' .. etag,
    '',
    body or '',
  }, '\r\n')
end

--- Stub `gh repo view` (run_str), the review comments fetch (run_result) and the
--- GraphQL thread status query (run). `responses` are consumed in order.
local function reload_gh_for_comments(responses)
  local api_calls = {}
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run_result = function(cmd)
      table.insert(api_calls, cmd)
      local response = table.remove(responses, 1)
      return { stdout = response, stderr = response:match('^HTTP/2.0 2') and '' or 'gh: HTTP 304', code = 0 }
    end,
    run = function()
      return '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}}'
    end,
  })
  return gh, restore, api_calls
end

local function capture_grouped_input()
  local comments_utils = require('ghlite.comments_utils')
  local original = comments_utils.group_comments
  local captured = {}
  comments_utils.group_comments = function(comments)
    table.insert(captured, comments)
    return { grouped = true }
  end
  return captured, function()
    comments_utils.group_comments = original
  end
end

T['load_comments filters comments without a line before grouping'] = function()
  local grouped, restore_grouping = capture_grouped_input()
  local gh, restore, api_calls = reload_gh_for_comments({
    http_response('200 OK', 'W/"a"', '[{"id":1,"line":10},{"id":2,"line":null}]'),
  })

  local result = async
    .run(function()
      return gh.load_comments(12)
    end)
    :wait(1000)
  restore()
  restore_grouping()

  expect.equality(api_calls, { { 'gh', 'api', '-i', 'repos/owner/repo/pulls/12/comments' } })
  expect.equality(#grouped[1], 1)
  expect.equality(grouped[1][1].id, 1)
  expect.equality(result, { grouped = true })
end

T['load_comments keeps outdated comments that carry original_line but no line'] = function()
  local grouped, restore_grouping = capture_grouped_input()
  local gh, restore = reload_gh_for_comments({
    http_response('200 OK', 'W/"a"', '[{"id":1,"line":10},{"id":2,"line":null,"original_line":7}]'),
  })

  local result = async
    .run(function()
      return gh.load_comments(12)
    end)
    :wait(1000)
  restore()
  restore_grouping()

  expect.equality(#grouped[1], 2)
  expect.equality(grouped[1][2].id, 2)
  expect.equality(result, { grouped = true })
end

T['load_comments revalidates with the ETag and reuses the body on 304'] = function()
  local grouped, restore_grouping = capture_grouped_input()
  local gh, restore, api_calls = reload_gh_for_comments({
    http_response('200 OK', 'W/"first"', '[{"id":1,"line":10}]'),
    http_response('304 Not Modified', 'W/"first"'),
    http_response('200 OK', 'W/"second"', '[{"id":1,"line":10},{"id":3,"line":12}]'),
  })

  async
    .run(function()
      gh.load_comments(12)
      gh.load_comments(12)
      gh.load_comments(12)
    end)
    :wait(1000)
  restore()
  restore_grouping()

  expect.equality(api_calls[2], {
    'gh',
    'api',
    '-H',
    'If-None-Match: W/"first"',
    '-i',
    'repos/owner/repo/pulls/12/comments',
  })
  expect.equality(api_calls[3][4], 'If-None-Match: W/"first"')
  expect.equality(
    vim.tbl_map(function(c)
      return #c
    end, grouped),
    { 1, 1, 2 }
  )
end

T['get_pending_comments reads draft ranges off the review thread'] = function()
  local threads = {
    {
      path = 'a.lua',
      line = 17,
      startLine = 15,
      comments = { nodes = { { databaseId = 1, state = 'PENDING', author = { login = 'alice' }, body = 'Range' } } },
    },
    {
      path = 'b.lua',
      line = 4,
      startLine = 4,
      comments = {
        nodes = {
          { databaseId = 2, state = 'SUBMITTED', author = { login = 'bob' }, body = 'Root' },
          { databaseId = 3, state = 'PENDING', author = { login = 'alice' }, body = 'Draft reply' },
        },
      },
    },
    -- Outdated beyond recovery: neither the current nor the original range survives.
    {
      path = 'c.lua',
      line = vim.NIL,
      startLine = vim.NIL,
      originalLine = vim.NIL,
      comments = { nodes = { { databaseId = 4, state = 'PENDING', author = { login = 'alice' }, body = 'Lost' } } },
    },
  }
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function()
      return vim.json.encode({
        data = {
          repository = { pullRequest = { reviewThreads = { nodes = threads, pageInfo = { hasNextPage = false } } } },
        },
      })
    end,
  })

  local comments = async
    .run(function()
      return gh.get_pending_comments({ id = 5, node_id = 'PRR_1', pr_number = 12 })
    end)
    :wait(1000)
  restore()

  expect.equality(#comments, 2)
  expect.equality(comments[1].id, 1)
  expect.equality(comments[1].line, 17)
  expect.equality(comments[1].start_line, 15)
  expect.equality(comments[1].path, 'a.lua')
  expect.equality(comments[1].pending, true)
  expect.equality(comments[1].in_reply_to_id, nil)
  expect.equality(comments[2].id, 3)
  expect.equality(comments[2].in_reply_to_id, 2)
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

--- Pair up the -f/-F flags of a `gh api` request so assertions do not depend on
--- argument order or on the exact text of a GraphQL query.
local function api_fields(request)
  local fields = {}
  for i = 1, #request - 1 do
    if request[i] == '-f' or request[i] == '-F' then
      local name, value = request[i + 1]:match('^([^=]+)=(.*)$')
      fields[name] = value
    end
  end
  return fields
end

T['get_pending_review picks the pending review and ignores submitted ones'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      if cmd == 'gh repo view --json nameWithOwner -q .nameWithOwner' then
        return 'owner/repo\n', ''
      end
      expect.equality(cmd, 'gh api repos/owner/repo/pulls/12/reviews')
      return '[{"id":1,"node_id":"PRR_one","state":"APPROVED"},{"id":2,"node_id":"PRR_two","state":"PENDING"}]', ''
    end,
  })

  local review = async
    .run(function()
      return gh.get_pending_review(12)
    end)
    :wait(1000)
  restore()

  expect.equality(review, { id = 2, node_id = 'PRR_two', pr_number = 12 })
end

T['get_pending_review returns nil when every review was submitted'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function(cmd)
      if cmd == 'gh repo view --json nameWithOwner -q .nameWithOwner' then
        return 'owner/repo\n', ''
      end
      return '[{"id":1,"node_id":"PRR_one","state":"COMMENTED"}]', ''
    end,
  })

  local review = async
    .run(function()
      return gh.get_pending_review(12)
    end)
    :wait(1000)
  restore()

  expect.equality(review, nil)
end

T['new_pending_comment attaches the comment to the review without a start line'] = function()
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"data":{"addPullRequestReviewThread":{"thread":{"id":"PRRT_1","comments":{"nodes":[{"databaseId":9}]}}}}}'
    end,
  })

  local thread = async
    .run(function()
      return gh.new_pending_comment({ id = 5, node_id = 'PRR_two', pr_number = 12 }, 'Body', 'lua/example.lua', 5, 5)
    end)
    :wait(1000)
  restore()

  local fields = api_fields(api_request)
  expect.equality(api_request[3], 'graphql')
  expect.equality(fields.query:match('addPullRequestReviewThread') ~= nil, true)
  expect.equality(fields.query:match('pullRequestReviewId') ~= nil, true)
  expect.equality(fields.reviewId, 'PRR_two')
  expect.equality(fields.path, 'lua/example.lua')
  expect.equality(fields.line, '5')
  -- A single-line comment has no range to describe.
  expect.equality(fields.startLine, nil)
  expect.equality(fields.startSide, nil)
  expect.equality(thread.id, 'PRRT_1')
end

T['new_pending_comment sends startLine and startSide for ranges'] = function()
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"data":{"addPullRequestReviewThread":{"thread":{"id":"PRRT_1","comments":{"nodes":[{"databaseId":9}]}}}}}'
    end,
  })

  async
    .run(function()
      return gh.new_pending_comment({ id = 5, node_id = 'PRR_two', pr_number = 12 }, 'Body', 'lua/example.lua', 3, 5)
    end)
    :wait(1000)
  restore()

  local fields = api_fields(api_request)
  expect.equality(fields.line, '5')
  expect.equality(fields.startLine, '3')
  expect.equality(fields.startSide, 'RIGHT')
end

T['new_pending_comment returns nil when GraphQL reports an error'] = function()
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function()
      return '{"errors":[{"message":"pull_request_review_thread.line must be part of the diff"}]}'
    end,
  })

  local thread = async
    .run(function()
      return gh.new_pending_comment({ id = 5, node_id = 'PRR_two', pr_number = 12 }, 'Body', 'a.lua', 5, 5)
    end)
    :wait(1000)
  restore()

  expect.equality(thread, nil)
end

T['submit_review posts the event to the review and omits an empty body'] = function()
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"id":5,"state":"APPROVED"}'
    end,
  })

  local resp = async
    .run(function()
      return gh.submit_review({ id = 5, node_id = 'PRR_two', pr_number = 12 }, 'APPROVE')
    end)
    :wait(1000)
  restore()

  expect.equality(api_request, {
    'gh',
    'api',
    '--method',
    'POST',
    'repos/owner/repo/pulls/12/reviews/5/events',
    '-f',
    'event=APPROVE',
  })
  expect.equality(resp.state, 'APPROVED')
end

T['submit_review sends the body required by non-approving events'] = function()
  local api_request
  local gh, restore = reload_gh_with_system({
    run_str = function()
      return 'owner/repo\n', ''
    end,
    run = function(cmd)
      api_request = cmd
      return '{"id":5,"state":"CHANGES_REQUESTED"}'
    end,
  })

  async
    .run(function()
      return gh.submit_review({ id = 5, node_id = 'PRR_two', pr_number = 12 }, 'REQUEST_CHANGES', 'Please fix')
    end)
    :wait(1000)
  restore()

  expect.equality(api_fields(api_request), { event = 'REQUEST_CHANGES', body = 'Please fix' })
end

return T
