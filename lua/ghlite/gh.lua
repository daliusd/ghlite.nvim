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
      'gh pr view %s --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt',
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
--- @return table<string, GroupedComment[]>
function M.load_comments(pr_number)
  local repo = get_repo()
  config.log('repo', repo)
  local comments_json = system.run_str(f('gh api repos/%s/pulls/%d/comments', repo, pr_number))
  local comments = parse_or_default(comments_json, {})
  config.log('comments', comments)

  local function is_valid_comment(comment)
    return comment.line ~= vim.NIL
  end

  comments = utils.filter_array(comments, is_valid_comment)
  config.log('Valid comments count', #comments)
  config.log('comments', comments)

  local grouped_comments = comments_utils.group_comments(comments, { comment_hunk = config.s.comment_hunk })
  config.log('Valid comments groups count:', #grouped_comments)
  config.log('grouped comments', grouped_comments)

  return grouped_comments
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
    'gh pr list --json number,title,author,createdAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,baseRefOid,labels'
  )
  config.log('get_pr_list resp', resp)

  local prefix = 'Unknown JSON field'
  if string.sub(stderr, 1, #prefix) == prefix then
    local resp2 = system.run_str(
      'gh pr list --json number,title,author,createdAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,labels'
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
