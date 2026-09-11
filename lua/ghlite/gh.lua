local comments_utils = require('ghlite.comments_utils')
local config = require('ghlite.config')
local system = require('ghlite.system')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

require('ghlite.types')

local f = string.format

local M = {}

local function parse_or_default(str, default)
  local success, result = pcall(vim.json.decode, str)
  if success then
    return result
  end

  return default
end

--- @async
--- @param silent boolean|nil suppress expected gh errors when probing passively
--- @return PullRequest|nil
function M.get_current_pr(silent)
  local result, stderr =
    system.run_str('gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision', silent)

  local prefix = 'Unknown JSON field'
  if result == nil then
    return nil
  elseif string.sub(stderr, 1, #prefix) == prefix then
    local result2 = system.run_str('gh pr view --json headRefName,headRefOid,number,baseRefName,reviewDecision', silent)
    if result2 == nil then
      return nil
    end
    return parse_or_default(result2, nil)
  else
    return parse_or_default(result, nil)
  end
end

--- @async
function M.get_pr_info(pr_number)
  local fields =
    'url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits,statusCheckRollup'
  local result, stderr = system.run_str(f('gh pr view %s --json %s', pr_number, fields))

  -- Keep the PR view usable with gh versions from before statusCheckRollup.
  if string.sub(stderr or '', 1, #'Unknown JSON field') == 'Unknown JSON field' then
    fields = fields:gsub(',statusCheckRollup', '')
    result = system.run_str(f('gh pr view %s --json %s', pr_number, fields))
  end

  if result == nil then
    return nil
  end
  config.log('get_pr_info resp', result)

  return parse_or_default(result, nil)
end

--- @async
--- @return string|nil
local function get_repo()
  local result = system.run_str('gh repo view --json nameWithOwner -q .nameWithOwner')
  if result ~= nil then
    return vim.split(result, '\n')[1]
  end
end

--- @async
--- @param pr_number number
--- @return { filename: string, status: string }[]|nil
function M.get_changed_files(pr_number)
  local repo = get_repo()
  if repo == nil then
    return nil
  end

  local result = system.run_str(f('gh api repos/%s/pulls/%d/files?per_page=100', repo, pr_number))
  if result == nil then
    return nil
  end

  config.log('get_changed_files resp', result)
  return parse_or_default(result, nil)
end

--- @async
--- @param sha string
--- @return CommitDetails|nil
function M.get_commit(sha)
  local repo = get_repo()
  if repo == nil then
    return nil
  end

  -- NOTE: run (not run_str) so a missing commit does not notify raw gh stderr
  local result = system.run({ 'gh', 'api', f('repos/%s/commits/%s', repo, sha) })
  config.log('get_commit resp', result)

  return parse_or_default(result, nil)
end

--- @async
--- @param sha string
--- @return { name: string, status: string, conclusion: string }[]|nil
function M.get_commit_checks(sha)
  local repo = get_repo()
  if repo == nil then
    return nil
  end

  local result = system.run({ 'gh', 'api', f('repos/%s/commits/%s/check-runs', repo, sha) })
  config.log('get_commit_checks resp', result)

  local resp = parse_or_default(result, nil)
  if resp == nil then
    return nil
  end

  return resp.check_runs
end

--- Last review-comments response body per PR with the ETag it was served under.
--- A poll that returns 304 costs no rate limit; the cached body is parsed again.
--- @type table<number, { etag: string, body: string }>
local comments_cache = {}

--- Split `gh api -i` output into status code, headers and body.
--- @param output string
--- @return integer|nil status
--- @return table<string, string> headers lower-cased names
--- @return string body
local function parse_http_response(output)
  local header_end = output:find('\r?\n\r?\n')
  if header_end == nil then
    return nil, {}, output
  end
  local head = output:sub(1, header_end - 1)
  local body = output:sub(header_end):gsub('^\r?\n\r?\n', '')

  local status = tonumber(head:match('^HTTP/[%d.]+ (%d+)'))
  local headers = {}
  for name, value in head:gmatch('\r?\n([^:\r\n]+):%s*([^\r\n]*)') do
    headers[name:lower()] = value
  end
  return status, headers, body
end

--- @async
--- @param repo string
--- @param pr_number number
--- @return table[] REST review comments
local function fetch_review_comments(repo, pr_number)
  local request = { 'gh', 'api', '-i', f('repos/%s/pulls/%d/comments', repo, pr_number) }
  local cached = comments_cache[pr_number]
  if cached ~= nil then
    table.insert(request, 3, '-H')
    table.insert(request, 4, 'If-None-Match: ' .. cached.etag)
  end

  local result = system.run_result(request)
  local status, headers, body = parse_http_response(result.stdout)
  config.log('review comments status', status)

  if status == 304 and cached ~= nil then
    return parse_or_default(cached.body, {})
  end
  if status ~= 200 then
    -- gh exits non-zero for every non-2xx status, so its stderr is the only error text.
    ui.notify(result.stderr, vim.log.levels.ERROR)
    return {}
  end
  if headers.etag ~= nil then
    comments_cache[pr_number] = { etag = headers.etag, body = body }
  end
  return parse_or_default(body, {})
end

--- @async
--- @param pr_number number
--- @param pending_review PendingReview|nil include the comments held in this review
--- @return table<string, GroupedComment[]>
function M.load_comments(pr_number, pending_review)
  local repo = get_repo()
  config.log('repo', repo)
  local comments = fetch_review_comments(repo, pr_number)
  config.log('comments', comments)

  local function is_valid_comment(comment)
    return comment.line ~= vim.NIL or (comment.original_line ~= nil and comment.original_line ~= vim.NIL)
  end

  comments = utils.filter_array(comments, is_valid_comment)
  config.log('Valid comments count', #comments)
  config.log('comments', comments)

  if pending_review ~= nil then
    for _, comment in ipairs(M.get_pending_comments(pending_review)) do
      table.insert(comments, comment)
    end
  end

  local thread_statuses = M.get_review_thread_statuses(pr_number, repo)
  local grouped_comments =
    comments_utils.group_comments(comments, { comment_hunk = config.s.comment_hunk }, thread_statuses)
  config.log('Valid comments groups count:', #grouped_comments)
  config.log('grouped comments', grouped_comments)

  return grouped_comments
end

--- Return resolution metadata keyed by the root REST review-comment ID.
--- GitHub exposes review-thread resolution only through GraphQL.
--- @async
function M.get_review_thread_statuses(pr_number, repo)
  repo = repo or get_repo()
  if repo == nil then
    return {}
  end
  local owner, name = repo:match('^([^/]+)/(.+)$')
  if owner == nil then
    return {}
  end

  local query = [[query($owner: String!, $name: String!, $number: Int!, $after: String) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100, after: $after) {
          nodes { id isResolved comments(first: 1) { nodes { databaseId } } }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }]]
  local statuses, after = {}, nil
  repeat
    local request = {
      'gh',
      'api',
      'graphql',
      '-f',
      'query=' .. query,
      '-f',
      'owner=' .. owner,
      '-f',
      'name=' .. name,
      '-F',
      'number=' .. pr_number,
    }
    if after ~= nil then
      table.insert(request, '-f')
      table.insert(request, 'after=' .. after)
    end
    local response = parse_or_default(system.run(request), {})
    local threads = type(response.data) == 'table'
      and type(response.data.repository) == 'table'
      and type(response.data.repository.pullRequest) == 'table'
      and response.data.repository.pullRequest.reviewThreads
    if type(threads) ~= 'table' then
      config.log('get_review_thread_statuses failed', response)
      break
    end
    for _, thread in ipairs(threads.nodes or {}) do
      local root = thread.comments and thread.comments.nodes and thread.comments.nodes[1]
      if root and root.databaseId then
        statuses[root.databaseId] = { thread_id = thread.id, resolved = thread.isResolved }
      end
    end
    after = threads.pageInfo and threads.pageInfo.hasNextPage and threads.pageInfo.endCursor or nil
  until after == nil

  return statuses
end

--- @async
function M.set_review_thread_resolved(thread_id, resolved)
  local mutation_name = resolved and 'resolveReviewThread' or 'unresolveReviewThread'
  local query = string.format(
    'mutation($threadId: ID!) { %s(input: {threadId: $threadId}) { thread { id isResolved } } }',
    mutation_name
  )
  local response = parse_or_default(
    system.run({
      'gh',
      'api',
      'graphql',
      '-f',
      'query=' .. query,
      '-f',
      'threadId=' .. thread_id,
    }),
    {}
  )
  local result = type(response.data) == 'table' and response.data[mutation_name]
  if result and result.thread then
    return result.thread
  end
  config.log('set_review_thread_resolved failed', response)
  return nil
end

--- @async
function M.reply_to_comment(pr_number, body, reply_to)
  local repo = get_repo()
  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f('repos/%s/pulls/%d/comments', repo, pr_number),
    '-f',
    'body=' .. body,
    '-F',
    'in_reply_to=' .. reply_to,
  }
  config.log('reply_to_comment request', request)

  local result = system.run(request)
  local resp = parse_or_default(result, { errors = {} })

  config.log('reply_to_comment resp', resp)
  return resp
end

--- @async
function M.new_comment(selected_pr, body, path, start_line, line)
  local repo = get_repo()
  local commit_id = selected_pr.headRefOid

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f('repos/%s/pulls/%d/comments', repo, selected_pr.number),
    '-f',
    'body=' .. body,
    '-f',
    'commit_id=' .. commit_id,
    '-f',
    'path=' .. path,
    '-F',
    'line=' .. line,
    '-f',
    'side=RIGHT',
  }

  if start_line ~= line then
    table.insert(request, '-F')
    table.insert(request, 'start_line=' .. start_line)
  end

  config.log('new_comment request', request)

  local result = system.run(request)
  local resp = parse_or_default(result, { errors = {} })
  config.log('new_comment resp', resp)
  return resp
end

--- Pending reviews are created, submitted and discarded over REST, which keys them by
--- PR number, while comments are attached over GraphQL, the only API that takes a review
--- id together with file line numbers.

--- @async
--- @param pr_number number
--- @return PendingReview|nil
function M.get_pending_review(pr_number)
  local repo = get_repo()
  if repo == nil then
    return nil
  end

  local resp = parse_or_default(system.run_str(f('gh api repos/%s/pulls/%d/reviews', repo, pr_number)), {})
  for _, review in ipairs(resp) do
    -- GitHub shows a pending review only to its author and allows one at a time.
    if review.state == 'PENDING' then
      return { id = review.id, node_id = review.node_id, pr_number = pr_number }
    end
  end
  return nil
end

--- @async
--- @param pr_number number
--- @return PendingReview|nil
function M.start_review(pr_number)
  local repo = get_repo()
  -- No event means the review stays pending.
  local request = { 'gh', 'api', '--method', 'POST', f('repos/%s/pulls/%d/reviews', repo, pr_number) }
  config.log('start_review request', request)

  local resp = parse_or_default(system.run(request), {})
  config.log('start_review resp', resp)
  if resp.id == nil or resp.node_id == nil then
    return nil
  end
  return { id = resp.id, node_id = resp.node_id, pr_number = pr_number }
end

--- Comments held in a pending review, which the PR comments listing omits.
--- They carry no line, side or position, so the line is recovered from the diff hunk.
--- @async
--- @param review PendingReview
--- @return table[] REST-shaped review comments
function M.get_pending_comments(review)
  local repo = get_repo()
  if repo == nil then
    return {}
  end

  local resp = parse_or_default(
    system.run_str(f('gh api repos/%s/pulls/%d/reviews/%d/comments', repo, review.pr_number, review.id)),
    {}
  )
  if type(resp) ~= 'table' or resp.message ~= nil then
    config.log('get_pending_comments failed', resp)
    return {}
  end

  local comments = {}
  for _, comment in ipairs(resp) do
    if comment.line == nil or comment.line == vim.NIL then
      comment.line = comments_utils.line_from_diff_hunk(comment.diff_hunk)
      comment.side = 'RIGHT'
    end
    comment.pending = true
    if comment.line ~= nil then
      table.insert(comments, comment)
    end
  end
  config.log('pending comments count', #comments)
  return comments
end

local pending_comment_fields = 'databaseId url body updatedAt path diffHunk author { login }'

--- @async
--- @param review PendingReview
--- @param body string
--- @param path string
--- @param start_line number
--- @param line number
--- @return table|nil thread GraphQL thread node with its first comment
function M.new_pending_comment(review, body, path, start_line, line)
  local query = f(
    [[mutation($reviewId: ID!, $path: String!, $body: String!, $line: Int!, $startLine: Int, $startSide: DiffSide) {
    addPullRequestReviewThread(input: {
      pullRequestReviewId: $reviewId,
      path: $path,
      body: $body,
      line: $line,
      side: RIGHT,
      startLine: $startLine,
      startSide: $startSide
    }) {
      thread { id isResolved comments(first: 1) { nodes { %s } } }
    }
  }]],
    pending_comment_fields
  )

  local request = {
    'gh',
    'api',
    'graphql',
    '-f',
    'query=' .. query,
    '-f',
    'reviewId=' .. review.node_id,
    '-f',
    'path=' .. path,
    '-f',
    'body=' .. body,
    '-F',
    'line=' .. line,
  }

  -- A single-line comment has no range, so startLine and startSide stay null.
  if start_line ~= line then
    table.insert(request, '-F')
    table.insert(request, 'startLine=' .. start_line)
    table.insert(request, '-f')
    table.insert(request, 'startSide=RIGHT')
  end

  config.log('new_pending_comment request', request)
  local resp = parse_or_default(system.run(request), {})
  config.log('new_pending_comment resp', resp)

  local result = type(resp.data) == 'table' and resp.data.addPullRequestReviewThread
  if type(result) == 'table' and type(result.thread) == 'table' then
    return result.thread
  end
  return nil
end

--- @async
--- @param review PendingReview
--- @param body string
--- @param thread_id string GraphQL review-thread id
--- @return table|nil comment GraphQL comment node
function M.reply_to_pending_comment(review, body, thread_id)
  local query = f(
    [[mutation($reviewId: ID!, $threadId: ID!, $body: String!) {
    addPullRequestReviewThreadReply(input: {
      pullRequestReviewId: $reviewId,
      pullRequestReviewThreadId: $threadId,
      body: $body
    }) {
      comment { %s }
    }
  }]],
    pending_comment_fields
  )

  local request = {
    'gh',
    'api',
    'graphql',
    '-f',
    'query=' .. query,
    '-f',
    'reviewId=' .. review.node_id,
    '-f',
    'threadId=' .. thread_id,
    '-f',
    'body=' .. body,
  }
  config.log('reply_to_pending_comment request', request)

  local resp = parse_or_default(system.run(request), {})
  config.log('reply_to_pending_comment resp', resp)

  local result = type(resp.data) == 'table' and resp.data.addPullRequestReviewThreadReply
  if type(result) == 'table' and type(result.comment) == 'table' then
    return result.comment
  end
  return nil
end

--- @async
--- @param review PendingReview
--- @param event 'APPROVE'|'REQUEST_CHANGES'|'COMMENT'
--- @param body string|nil required by GitHub for every event except APPROVE
--- @return table|nil
function M.submit_review(review, event, body)
  local repo = get_repo()
  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f('repos/%s/pulls/%d/reviews/%d/events', repo, review.pr_number, review.id),
    '-f',
    'event=' .. event,
  }

  if body ~= nil and body ~= '' then
    table.insert(request, '-f')
    table.insert(request, 'body=' .. body)
  end

  config.log('submit_review request', request)
  local resp = parse_or_default(system.run(request), {})
  config.log('submit_review resp', resp)

  if resp.id == nil then
    return nil
  end
  return resp
end

--- @async
--- @param review PendingReview
--- @return boolean deleted
function M.discard_review(review)
  local repo = get_repo()
  local request = {
    'gh',
    'api',
    '--method',
    'DELETE',
    f('repos/%s/pulls/%d/reviews/%d', repo, review.pr_number, review.id),
  }
  config.log('discard_review request', request)

  local resp = parse_or_default(system.run(request), {})
  config.log('discard_review resp', resp)
  return resp.id ~= nil
end

--- @async
function M.new_pr_comment(selected_pr, body)
  local request = {
    'gh',
    'pr',
    'comment',
    f('%d', selected_pr.number),
    '--body',
    body,
  }

  config.log('new_pr_comment request', request)

  local result = system.run(request)
  config.log('new_pr_comment resp', result)
  return result
end

--- @async
function M.update_comment(comment_id, body)
  local repo = get_repo()
  local request = {
    'gh',
    'api',
    '--method',
    'PATCH',
    f('repos/%s/pulls/comments/%s', repo, comment_id),
    '-f',
    'body=' .. body,
  }
  config.log('update_comment request', request)

  local result = system.run(request)
  local resp = parse_or_default(result, { errors = {} })
  config.log('update_comment resp', resp)
  return resp
end

--- @async
function M.delete_comment(comment_id)
  local repo = get_repo()
  local request = {
    'gh',
    'api',
    '--method',
    'DELETE',
    f('repos/%s/pulls/comments/%s', repo, comment_id),
  }
  config.log('delete_comment request', request)

  local resp = system.run(request)
  config.log('delete_comment resp', resp)
  return resp
end

--- @async
--- @return PullRequest[]
function M.get_pr_list()
  local fields =
    'number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels,statusCheckRollup'
  local resp, stderr = system.run_str('gh pr list --json ' .. fields)
  config.log('get_pr_list resp', resp)

  if string.sub(stderr or '', 1, #'Unknown JSON field') == 'Unknown JSON field' then
    fields = fields:gsub(',baseRefOid', ''):gsub(',statusCheckRollup', '')
    resp = system.run_str('gh pr list --json ' .. fields)
    config.log('get_pr_list resp', resp)
  end

  return parse_or_default(resp, {})
end

--- @async
--- @param number number
function M.checkout_pr(number)
  return system.run_str(f('gh pr checkout %d', number))
end

--- @async
function M.approve_pr(number)
  return system.run_str(f('gh pr review %s -a', number))
end

--- @async
function M.request_changes_pr(number, body)
  local request = {
    'gh',
    'pr',
    'review',
    f('%d', number),
    '-r',
    '--body',
    body,
  }

  config.log('request_changes_pr request', request)

  local result = system.run(request)
  config.log('request_changes_pr resp', result)
  return result
end

--- @async
function M.get_pr_diff(number)
  return system.run_str(f('gh pr diff %s', number))
end

--- @async
function M.merge_pr(number, options)
  return system.run_str(f('gh pr merge %s %s', number, options))
end

--- @async
--- @return string|nil
function M.get_user()
  local result = system.run_str('gh api user -q .login')
  if result ~= nil then
    return vim.split(result, '\n')[1]
  end
end

return M
