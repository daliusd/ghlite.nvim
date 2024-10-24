local utils = require "ghlite.utils"
local config = require "ghlite.config"

require "ghlite.types"

local f = string.format
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

--- @return Comment: extracted gh comment
function M.convert_comment(comment)
  return {
    id = comment.id,
    url = comment.html_url,
    path = comment.path,
    line = comment.start_line ~= vim.NIL and comment.start_line or comment.line,
    user = comment.user.login,
    body = comment.body,
    updated_at = comment.updated_at,
    diff_hunk = comment.diff_hunk,
  }
end

--- @param comment Comment
function M.format_comment(comment)
  return string.format("✍️ %s at %s:\n%s\n\n", comment.user, comment.updated_at, string.gsub(comment.body, "\r", ""))
end

local function group_comments(comments)
  --- @type table<number, Comment[]>
  local comment_groups = {}
  local base = {}
  local git_root = utils.get_git_root()

  for _, comment in pairs(comments) do
    if comment.in_reply_to_id == nil then
      comment_groups[comment.id] = { M.convert_comment(comment) }
      base[comment.id] = comment.id
    else
      table.insert(comment_groups[base[comment.in_reply_to_id]], M.convert_comment(comment))
      base[comment.id] = base[comment.in_reply_to_id]
    end
  end

  --- @type table<string, GroupedComment[]>
  local result = {}
  for _, comment_group in pairs(comment_groups) do
    --- @type GroupedComment
    local grouped_comments = {
      id = comment_group[1].id,
      line = comment_group[1].line,
      url = comment_group[#comment_group].url,
      content = "",
    }
    for _, comment in pairs(comment_group) do
      grouped_comments.content = grouped_comments.content .. M.format_comment(comment)
    end

    grouped_comments.content = grouped_comments.content .. '\n' .. comment_group[1].diff_hunk .. '\n'

    local full_path = git_root .. '/' .. comment_group[1].path
    if result[full_path] == nil then
      result[full_path] = { grouped_comments }
    else
      table.insert(result[full_path], grouped_comments)
    end
  end

  return result
end

function M.get_current_pr()
  return utils.system_str('gh pr view --json number -q .number')[1]
end

function M.load_comments(pr)
  local repo = utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
  config.log("repo", repo)

  local comments = json.parse(utils.system_str(f("gh api repos/%s/pulls/%d/comments", repo, pr)))
  config.log("comments", comments)

  local function is_valid_comment(comment)
    return comment.line ~= vim.NIL
  end

  comments = utils.filter_array(comments, is_valid_comment)
  config.log('Valid comments count', #comments)
  config.log('comments', comments)

  comments = group_comments(comments)
  config.log('Valid comments groups count:', #comments)
  config.log('grouped comments', comments)

  return comments
end

function M.reply_to_comment(body, reply_to)
  local repo = utils.system_str('gh repo view --json nameWithOwner -q .nameWithOwner')[1]
  local pr = M.get_current_pr()

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f("repos/%s/pulls/%d/comments", repo, pr),
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
  local pr = M.get_current_pr()
  local commit_id = utils.system_str("git rev-parse HEAD")[1]

  local request = {
    'gh',
    'api',
    '--method',
    'POST',
    f("repos/%s/pulls/%d/comments", repo, pr),
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
    'gh pr list --json number,title,author,createdAt,isDraft,reviewDecision,headRefName'))

  return resp
end

function M.checkout_pr(number)
  local resp = utils.system_str(f('gh pr checkout %s', number))
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
