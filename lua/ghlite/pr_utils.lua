-- To avoid accidental confusion commands are working only with two types of PRs:
-- * Selected (some commands don't need PR to be checked out)
-- * Checked Out (if command expects checked out state then it should check out selected branch)
--
-- * Some commands might work either with selected or checked out PR depending on view (diff view vs buffer)
--
-- If there is branch checked out but no PR Selected then this PR becomes Selected.

local gh = require('ghlite.gh')
local state = require('ghlite.state')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

require('ghlite.types')

local M = {}

--- @async
--- @return PullRequest|nil
function M.get_selected_pr()
  if state.selected_PR ~= nil then
    return state.selected_PR
  end
  local current_pr = gh.get_current_pr()
  if current_pr ~= nil then
    state.selected_PR = current_pr
    return current_pr
  end
  return nil
end

--- @async
--- @return PullRequest|nil pr checked out pr or nil if user does not approve check out
--- @return string|nil reason 'declined' when the user rejects the check out
local function approve_and_chechkout_selected_pr()
  local choice = ui.confirm('Do you want to check out selected PR?', '&Yes\n&No', 1)

  if choice ~= 1 then
    return nil, 'declined'
  end

  ui.notify(string.format('Checking out PR #%d...', state.selected_PR.number))
  gh.checkout_pr(state.selected_PR.number)
  ui.notify('PR check out finished.')
  return state.selected_PR
end

--- @async
--- @return boolean
function M.is_pr_checked_out()
  if state.selected_PR == nil then
    return false
  end
  return state.selected_PR.headRefName == utils.get_current_git_branch_name()
end

--- @async
--- @return PullRequest|nil pr pull request or nil in case pull request is not checked out
--- @return string|nil reason 'declined' when the user rejects the check out
function M.get_checked_out_pr()
  local current_branch = utils.get_current_git_branch_name()
  if state.selected_PR ~= nil then
    if state.selected_PR.headRefName ~= current_branch then
      return approve_and_chechkout_selected_pr()
    end
    return state.selected_PR
  end

  local current_pr = gh.get_current_pr()
  if current_pr ~= nil then
    state.selected_PR = current_pr
    return current_pr
  end
  return nil
end

return M
