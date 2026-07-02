local async = require('async')

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

    local result = async
      .run(function()
        return pr_utils.get_selected_pr()
      end)
      :wait(1000)

    expect.equality(result, state.selected_PR)
  end)
end

T['get_selected_pr stores current PR when none is selected'] = function()
  reset_state()
  local current_pr = { number = 42, headRefName = 'feature' }

  with_overrides({
    ['ghlite.gh'] = {
      get_current_pr = function()
        return current_pr
      end,
    },
  }, function()
    local state = require('ghlite.state')
    local pr_utils = require('ghlite.pr_utils')

    local result = async
      .run(function()
        return pr_utils.get_selected_pr()
      end)
      :wait(1000)

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
      get_current_git_branch_name = function()
        return 'feature'
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')

    local result = async
      .run(function()
        return pr_utils.is_pr_checked_out()
      end)
      :wait(1000)

    expect.equality(result, true)
  end)
end

T['get_checked_out_pr checks out selected PR after confirmation when branch differs'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.selected_PR = { number = 9, headRefName = 'feature' }

  local notified = {}
  local checked_out_number

  with_overrides({
    ['ghlite.utils'] = {
      get_current_git_branch_name = function()
        return 'main'
      end,
    },
    ['ghlite.ui'] = {
      confirm = function(message, choices, default)
        expect.equality(message, 'Do you want to check out selected PR?')
        expect.equality(choices, '&Yes\n&No')
        expect.equality(default, 1)
        return 1
      end,
      notify = function(message)
        table.insert(notified, message)
      end,
    },
    ['ghlite.gh'] = {
      checkout_pr = function(number)
        checked_out_number = number
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')

    local result = async
      .run(function()
        return pr_utils.get_checked_out_pr()
      end)
      :wait(1000)

    expect.equality(checked_out_number, 9)
    expect.equality(result, state.selected_PR)
    expect.equality(notified, { 'Checking out PR #9...', 'PR check out finished.' })
  end)
end

T['get_checked_out_pr stays silent when the user declines the check out'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.selected_PR = { number = 9, headRefName = 'feature' }

  with_overrides({
    ['ghlite.utils'] = {
      get_current_git_branch_name = function()
        return 'main'
      end,
    },
    ['ghlite.ui'] = {
      confirm = function()
        return 2
      end,
      notify = function()
        error('notify should not be called on decline')
      end,
    },
    ['ghlite.gh'] = {
      checkout_pr = function()
        error('checkout_pr should not be called on decline')
      end,
    },
  }, function()
    local pr_utils = require('ghlite.pr_utils')

    local result, reason = async
      .run(function()
        return pr_utils.get_checked_out_pr()
      end)
      :wait(1000)

    expect.equality(result, nil)
    expect.equality(reason, 'declined')
  end)
end

return T
