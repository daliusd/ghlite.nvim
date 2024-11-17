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

function M.get_selected_pr(cb)
  if state.selected_PR ~= nil then
    return cb(state.selected_PR)
  end
  gh.get_current_pr(function(current_pr)
    if current_pr ~= nil then
      state.selected_PR = current_pr
      cb(current_pr)
    else
      cb(nil)
    end
  end)
end

--- @return PullRequest|nil returns checked out pr or nil if user does not approve check out
local function approve_and_chechkout_selected_pr(cb)
  vim.schedule(function()
    local choice = vim.fn.confirm("Do you want to check out selected PR?", "&Yes\n&No", 1)

    if choice == 1 then
      utils.notify(string.format('Checking out PR #%d...', state.selected_PR.number))
      gh.checkout_pr(state.selected_PR.number, function()
        utils.notify('PR checked out.')
        cb(state.selected_PR)
      end)
    end
  end)
end

function M.is_pr_checked_out(cb)
  if state.selected_PR == nil then
    cb(false)
  else
    utils.get_current_git_branch_name(function(current_branch)
      cb(state.selected_PR.headRefName == current_branch)
    end)
  end
end

--- @return PullRequest|nil returns pull request or nil in case pull request is not checked out
function M.get_checked_out_pr(cb)
  utils.get_current_git_branch_name(function(current_branch)
    if state.selected_PR ~= nil then
      if state.selected_PR.headRefName ~= current_branch then
        approve_and_chechkout_selected_pr(cb)
      else
        cb(state.selected_PR)
      end
    else
      gh.get_current_pr(function(current_pr)
        if current_pr ~= nil then
          state.selected_PR = current_pr
          cb(current_pr)
        else
          cb(nil)
        end
      end)
    end
  end)
end

return M
