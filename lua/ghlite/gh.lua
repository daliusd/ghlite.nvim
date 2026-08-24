local comments_utils = require('ghlite.comments_utils')
local config = require('ghlite.config')
local system = require('ghlite.system')
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
--- @return PullRequest|nil
function M.get_current_pr()
  local result, stderr =
    system.run_str('gh pr view --json headRefName,headRefOid,number,baseRefName,baseRefOid,reviewDecision')

  local prefix = 'Unknown JSON field'
  if result == nil then
    return nil
  elseif string.sub(stderr, 1, #prefix) == prefix then
    local result2 = system.run_str('gh pr view --json headRefName,headRefOid,number,baseRefName,reviewDecision')
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
  local result = system.run_str(
    f(
      'gh pr view %s --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt,headRefName,commits',
      pr_number
    )
  )
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

--- @async
--- @param pr_number number
--- @return table<string, GroupedComment[]>
function M.load_comments(pr_number)
  local repo = get_repo()
  config.log('repo', repo)
  local comments_json = system.run_str(f('gh api repos/%s/pulls/%d/comments', repo, pr_number))
  local comments = parse_or_default(comments_json, {})
  config.log('comments', comments)

  local function is_valid_comment(comment)
    return comment.line ~= vim.NIL or (comment.original_line ~= nil and comment.original_line ~= vim.NIL)
  end

  comments = utils.filter_array(comments, is_valid_comment)
  config.log('Valid comments count', #comments)
  config.log('comments', comments)

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
  local resp, stderr = system.run_str(
    'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels'
  )
  config.log('get_pr_list resp', resp)

  local prefix = 'Unknown JSON field'
  if string.sub(stderr, 1, #prefix) == prefix then
    local resp2 = system.run_str(
      'gh pr list --json number,title,author,createdAt,updatedAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,labels'
    )
    config.log('get_pr_list resp', resp2)
    return parse_or_default(resp2, {})
  else
    return parse_or_default(resp, {})
  end
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
