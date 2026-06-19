local T = MiniTest.new_set()
local expect = MiniTest.expect

local function reset_state()
  package.loaded['ghlite.pr_utils'] = nil
  local state = require('ghlite.state')
  state.selected_PR = nil
  state.comments_list = {}
  state.diff_buffer_id = nil
  state.filename_line_to_diff_line = {}
  state.diff_line_to_filename_line = {}
end

local function with_overrides(overrides, fn)
  local originals = {}
  for module_name, module_overrides in pairs(overrides) do
    local module = require(module_name)
    originals[module_name] = { module = module, values = {} }
    for key, value in pairs(module_overrides) do
      originals[module_name].values[key] = module[key]
      module[key] = value
    end
  end

  local ok, err = pcall(fn)

  for _, original in pairs(originals) do
    for key, value in pairs(original.values) do
      original.module[key] = value
    end
  end

  if not ok then
    error(err)
  end
end

T['get_selected_pr returns already selected PR without calling gh'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.selected_PR = { number = 123, headRefName = 'feature' }

  with_overrides({
    ['ghlite.gh'] = {
      get_current_pr = function()
        error('get_current_pr should not be called')
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')
    local result

    pr_utils.get_selected_pr(function(pr)
      result = pr
    end)

    expect.equality(result, state.selected_PR)
  end)
end

T['get_selected_pr stores current PR when none is selected'] = function()
  reset_state()
  local current_pr = { number = 42, headRefName = 'feature' }

  with_overrides({
    ['ghlite.gh'] = {
      get_current_pr = function(cb)
        cb(current_pr)
      end,
    },
  }, function()
    local state = require('ghlite.state')
    local pr_utils = require('ghlite.pr_utils')
    local result

    pr_utils.get_selected_pr(function(pr)
      result = pr
    end)

    expect.equality(result, current_pr)
    expect.equality(state.selected_PR, current_pr)
  end)
end

T['is_pr_checked_out compares selected PR head branch to current branch'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.selected_PR = { number = 7, headRefName = 'feature' }

  with_overrides({
    ['ghlite.utils'] = {
      get_current_git_branch_name = function(cb)
        cb('feature')
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')
    local result

    pr_utils.is_pr_checked_out(function(is_checked_out)
      result = is_checked_out
    end)

    expect.equality(result, true)
  end)
end

T['get_checked_out_pr checks out selected PR after confirmation when branch differs'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.selected_PR = { number = 9, headRefName = 'feature' }

  local notified = {}
  local checked_out_number
  local original_schedule = vim.schedule
  local original_confirm = vim.fn.confirm
  vim.schedule = function(cb)
    cb()
  end
  vim.fn.confirm = function(message, choices, default)
    expect.equality(message, 'Do you want to check out selected PR?')
    expect.equality(choices, '&Yes\n&No')
    expect.equality(default, 1)
    return 1
  end

  with_overrides({
    ['ghlite.utils'] = {
      get_current_git_branch_name = function(cb)
        cb('main')
      end,
      notify = function(message)
        table.insert(notified, message)
      end,
    },
    ['ghlite.gh'] = {
      checkout_pr = function(number, cb)
        checked_out_number = number
        cb()
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')
    local result

    pr_utils.get_checked_out_pr(function(pr)
      result = pr
    end)

    expect.equality(checked_out_number, 9)
    expect.equality(result, state.selected_PR)
    expect.equality(notified, { 'Checking out PR #9...', 'PR check out finished.' })
  end)

  vim.schedule = original_schedule
  vim.fn.confirm = original_confirm
end

return T
