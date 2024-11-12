local utils = require "ghlite.utils"
local config = require "ghlite.config"
local comments_utils = require "ghlite.comments_utils"

require "ghlite.types"

local f = string.format

local M = {}

local function parse_or_default(str, default)
  local success, result = pcall(vim.fn.json_decode, str)
  if success then
    return result
  end

  return default
end

function M.get_current_pr()
  local result = utils.system_str('gh pr view --json headRefName,headRefOid,number,baseRefName,reviewDecision')
  if result[1] == nil then
    return nil
  end

  return parse_or_default(result, nil)
end

function M.get_pr_info(pr_number)
  local result = utils.system_str(f(
    'gh pr view %s --json url,author,title,number,labels,comments,reviews,body,changedFiles,isDraft,createdAt',
    pr_number))
  if result[1] == nil then
    return nil
  end

  return parse_or_default(result, nil)
end

local function get_repo()
  return utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
end

--- @params pr_number number
function M.load_comments(pr_number)
  local repo = get_repo()
  config.log("repo", repo)

  local comments = parse_or_default(utils.system_str(f("gh api repos/%s/pulls/%d/comments", repo, pr_number)), {})
  config.log("comments", comments)

  local function is_valid_comment(comment)
    return comment.line ~= vim.NIL
  end

  comments = utils.filter_array(comments, is_valid_comment)
  config.log('Valid comments count', #comments)
  config.log('comments', comments)

  comments = comments_utils.group_comments(comments)
  config.log('Valid comments groups count:', #comments)
  config.log('grouped comments', comments)

  return comments
end

function M.reply_to_comment(pr_number, body, reply_to)
  local repo = get_repo()

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f("repos/%s/pulls/%d/comments", repo, pr_number),
    "-f",
    "body=" .. body,
    "-F",
    "in_reply_to=" .. reply_to,
  }
  config.log('reply_to_comment request', request)

  local resp = parse_or_default(utils.system(request), { errors = {} })

  config.log("reply_to_comment resp", resp)
  return resp
end

function M.new_comment(selected_pr, body, path, start_line, line)
  local repo = get_repo()
  local commit_id = selected_pr.headRefOid

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f("repos/%s/pulls/%d/comments", repo, selected_pr.number),
    "-f",
    "body=" .. body,
    "-f",
    "commit_id=" .. commit_id,
    "-f",
    "path=" .. path,
    "-F",
    "line=" .. line,
    "-f",
    "side=RIGHT",
  }

  if start_line ~= line then
    table.insert(request, "-F")
    table.insert(request, "start_line=" .. start_line)
  end

  config.log('new_comment request', request)

  local resp = parse_or_default(utils.system(request), { errors = {} })

  config.log("new_comment resp", resp)
  return resp
end

function M.new_pr_comment(selected_pr, body)
  local repo = get_repo()

  local request = {
    'gh',
    'pr',
    'comment',
    f("%d", selected_pr.number),
    "--body",
    body,
  }

  config.log('new_pr_comment request', request)

  local result = utils.system(request)

  config.log("new_pr_comment resp", result)

  if result[1] == nil then
    return nil
  end

  return result
end

function M.update_comment(comment_id, body)
  local repo = get_repo()

  local request = {
    'gh',
    'api',
    '--method',
    'PATCH',
    f("repos/%s/pulls/comments/%s", repo, comment_id),
    "-f",
    "body=" .. body,
  }
  config.log('update_comment request', request)

  local resp = parse_or_default(utils.system(request), { errors = {} })

  config.log("update_comment resp", resp)
  return resp
end

function M.delete_comment(comment_id)
  local repo = get_repo()

  local request = {
    'gh',
    'api',
    '--method',
    'DELETE',
    f("repos/%s/pulls/comments/%s", repo, comment_id),
  }
  config.log('delete_comment request', request)

  local resp = utils.system(request)

  config.log("delete_comment resp", resp)
  return resp
end

function M.get_pr_list()
  local resp = parse_or_default(utils.system_str(
      'gh pr list --json number,title,author,createdAt,isDraft,reviewDecision,headRefName,headRefOid,baseRefName,labels'),
    {})
  config.log("get_pr_list resp", resp)

  return resp
end

--- @param number number
function M.checkout_pr(number)
  local resp = utils.system_str(f('gh pr checkout %d', number))
  return resp
end

function M.approve_pr(number)
  local resp = utils.system_str(f('gh pr review %s -a', number))
  return resp
end

function M.get_pr_diff(number)
  return utils.system_str(f('gh pr diff %s', number))
end

function M.merge_pr(number, options)
  return utils.system_str(f('gh pr merge %s %s', number, options))
end

function M.get_user()
  return utils.system_str('gh api user -q .login')[1]
end

return M
