local utils = require "ghlite.utils"
local config = require "ghlite.config"
local comments_utils = require "ghlite.comments_utils"
local state = require "ghlite.state"

require "ghlite.types"

local f = string.format
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

function M.get_current_pr()
  local result = utils.system_str('gh pr view --json headRefName,headRefOid,number')
  if result[1] == nil then
    return nil
  end

  return json.parse(result)
end

--- @params pr_number number
function M.load_comments(pr_number)
  local repo = utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
  config.log("repo", repo)

  local comments = json.parse(utils.system_str(f("gh api repos/%s/pulls/%d/comments", repo, pr_number)))
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

function M.reply_to_comment(body, reply_to)
  local repo = utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
  local selected_pr = state.selected_PR
  if selected_pr == nil then
    vim.notify('PR should be selected already', vim.log.levels.ERROR)
    return
  end

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f("repos/%s/pulls/%d/comments", repo, selected_pr.number),
    "-f",
    "body=" .. body,
    "-F",
    "in_reply_to=" .. reply_to,
  }
  config.log('reply_to_comment request', request)

  local resp = json.parse(utils.system(request))

  config.log("reply_to_comment resp", resp)
  return resp
end

function M.new_comment(body, path, line)
  local repo = utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
  local selected_pr = state.selected_PR
  if selected_pr == nil then
    vim.notify('PR should be selected already', vim.log.levels.ERROR)
    return
  end
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
  config.log('new_comment request', request)

  local resp = json.parse(utils.system(request))

  config.log("new_comment resp", resp)
  return resp
end

function M.get_pr_list()
  local resp = json.parse(utils.system_str(
    'gh pr list --json number,title,author,createdAt,isDraft,reviewDecision,headRefName,headRefOid'))

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

return M
