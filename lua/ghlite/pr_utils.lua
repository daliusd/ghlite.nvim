-- To avoid accidental confusion commands are working only with two types of PRs:
-- * Selected (some commands don't need PR to be checked out)
-- * Checked Out (if command expects checked out state then it should check out selected branch)
--
-- * Some commands might work either with selected or checked out PR depending on view (diff view vs buffer)
--
-- If there is branch checked out but no PR Selected then this PR becomes Selected.

local state = require "ghlite.state"
local utils = require "ghlite.utils"
local gh = require "ghlite.gh"

local M = {}

function M.get_selected_pr()
  if state.selected_PR ~= nil then
    return state.selected_PR
  end
  local current_pr = gh.get_current_pr()
  if current_pr ~= nil then
    state.selected_PR = current_pr
    return current_pr
  end
end

--- @return PullRequest|nil returns checked out pr or nil if user does not approve check out
local function approve_and_chechkout_selected_pr()
  local choice = vim.fn.confirm("Do you want to check out selected PR?", "&Yes\n&No", 1)

  if choice == 1 then
    vim.notify(string.format('Checking out PR #%d...', state.selected_PR.number))
    gh.checkout_pr(state.selected_PR.number)
    vim.notify('PR checked out.')
    return state.selected_PR
  end
end

function M.is_pr_checked_out()
  return state.selected_PR ~= nil and state.selected_PR.headRefName == utils.get_current_git_branch_name()
end

--- @return PullRequest|nil returns pull request or nil in case pull request is not checked out
function M.get_checked_out_pr()
  local current_branch = utils.get_current_git_branch_name()
  if state.selected_PR ~= nil then
    if state.selected_PR.headRefName ~= current_branch then
      local checked_out_pr = approve_and_chechkout_selected_pr()
      return checked_out_pr
    else
      return state.selected_PR
    end
  else
    local current_pr = gh.get_current_pr()
    if current_pr ~= nil then
      state.selected_PR = current_pr
      return current_pr
    end
  end
end

return M
