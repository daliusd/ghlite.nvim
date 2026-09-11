local T = MiniTest.new_set()
local expect = MiniTest.expect

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

T['ca on a PR view review-comment body replies to its thread'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  state.selected_PR = { number = 12, headRefName = 'feature' }
  state.comments_list = {}

  local reply_call
  local reply_initial_content
  with_overrides({
    ['ghlite.comments'] = {
      load_comments_only = function()
        state.comments_list = {
          [vim.fn.getcwd() .. '/lua/a.lua'] = {
            {
              id = 55,
              line = 2,
              comments = {
                {
                  user = 'alice',
                  updated_at = 'now',
                  body = 'Reply to this',
                  id = 55,
                  diff_hunk = '@@ -2 +2 @@',
                },
              },
            },
          },
        }
      end,
      reply_to_comment = function(pr_number, body, comment_group, on_success)
        reply_call = { pr_number = pr_number, body = body, reply_to = comment_group.id }
        on_success()
      end,
    },
    ['ghlite.gh'] = {
      get_pr_info = function()
        return {
          number = 12,
          title = 'Test PR',
          author = { login = 'alice' },
          createdAt = '2025-01-01',
          url = 'https://github.test/pr/12',
          headRefName = 'feature',
          changedFiles = 0,
          labels = {},
          reviews = {},
          body = '',
          commits = {},
          statusCheckRollup = {
            { name = 'build', status = 'COMPLETED', conclusion = 'SUCCESS' },
            { context = 'deploy', state = 'PENDING' },
          },
          comments = {},
        }
      end,
      get_changed_files = function()
        return {}
      end,
    },
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.utils'] = {
      get_current_git_branch_name = function()
        return 'feature'
      end,
      get_comment = function(_, _, _, content, _, callback)
        reply_initial_content = content
        callback('My reply')
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
      schedule = function() end,
    },
  }, function()
    pr_commands.load_pr_view():wait(1000)

    local buf = vim.api.nvim_get_current_buf()
    local body_line
    for line, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if text == 'Reply to this' then
        body_line = line
        break
      end
    end
    expect.no_equality(body_line, nil)
    local view_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    expect.equality(vim.tbl_contains(view_lines, '## Checks'), true)
    expect.equality(vim.tbl_contains(view_lines, '    ✓ build (SUCCESS)'), true)
    expect.equality(vim.tbl_contains(view_lines, '    ⏳ deploy (PENDING)'), true)
    expect.equality(vim.tbl_contains(view_lines, '### lua/a.lua:2 [unresolved]'), true)
    vim.api.nvim_win_set_cursor(0, { body_line, 0 })

    local keymap = vim.fn.maparg('ca', 'n', false, true)
    expect.no_equality(keymap.callback, nil)
    keymap.callback()
    vim.wait(1000, function()
      return reply_call ~= nil
    end)
  end)

  expect.equality(reply_initial_content, {
    '<!-- Type your PR comment and press c<CR> to comment: -->',
    '> Reply to this',
  })
  expect.equality(reply_call, { pr_number = 12, body = 'My reply', reply_to = 55 })
end

T['comment_on_pr quotes a PR comment and creates a top-level comment'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  state.selected_PR = { number = 12 }

  local initial_content
  local new_comment_call
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.utils'] = {
      get_comment = function(_, _, _, content, _, callback)
        initial_content = content
        callback('My response')
      end,
    },
    ['ghlite.gh'] = {
      new_pr_comment = function(pr, body)
        new_comment_call = { pr = pr, body = body }
        return { id = 1 }
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
      schedule = function() end,
    },
  }, function()
    pr_commands.comment_on_pr(nil, nil, { body = 'Original PR comment' }):wait(1000)
  end)

  expect.equality(initial_content, {
    '<!-- Type your PR comment and press c<CR> to comment: -->',
    '> Original PR comment',
  })
  expect.equality(new_comment_call, { pr = state.selected_PR, body = 'My response' })
end

T['start_review adopts the review GitHub already holds pending'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  state.selected_PR = { number = 12 }
  state.pending_reviews = {}

  local started = false
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.gh'] = {
      get_pending_review = function()
        return { id = 3, node_id = 'PRR_three', pr_number = 12 }
      end,
      start_review = function()
        started = true
        return { id = 4, node_id = 'PRR_four', pr_number = 12 }
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }, function()
    pr_commands.start_review():wait(1000)
  end)

  expect.equality(started, false)
  expect.equality(state.pending_reviews[12], { id = 3, node_id = 'PRR_three', pr_number = 12 })
  state.pending_reviews = {}
end

T['start_review keeps the pending review of another PR'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  local pr_utils = require('ghlite.pr_utils')
  state.selected_PR = { number = 12 }
  state.pending_reviews = { [99] = { id = 3, node_id = 'PRR_three', pr_number = 99 } }

  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.gh'] = {
      get_pending_review = function()
        return nil
      end,
      start_review = function()
        return { id = 4, node_id = 'PRR_four', pr_number = 12 }
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }, function()
    pr_commands.start_review():wait(1000)
  end)

  expect.equality(pr_utils.active_pending_review(99), { id = 3, node_id = 'PRR_three', pr_number = 99 })
  expect.equality(pr_utils.active_pending_review(12), { id = 4, node_id = 'PRR_four', pr_number = 12 })
  state.pending_reviews = {}
end

T['approve_pr submits the pending review instead of a standalone approval'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  state.selected_PR = { number = 12 }
  state.pending_reviews = { [12] = { id = 3, node_id = 'PRR_three', pr_number = 12 } }

  local submit_call
  local standalone_approve = false
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.gh'] = {
      submit_review = function(review, event, body)
        submit_call = { review = review, event = event, body = body }
        return { id = 3 }
      end,
      approve_pr = function()
        standalone_approve = true
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }, function()
    pr_commands.approve_pr():wait(1000)
  end)

  expect.equality(standalone_approve, false)
  expect.equality(submit_call.event, 'APPROVE')
  expect.equality(submit_call.review.id, 3)
  -- The review is gone once submitted, so later comments post immediately again.
  expect.equality(state.pending_reviews[12], nil)
end

T['approve_pr ignores a pending review left over from another PR'] = function()
  local state = require('ghlite.state')
  local pr_commands = require('ghlite.pr_commands')
  state.selected_PR = { number = 12 }
  state.pending_reviews = { [99] = { id = 3, node_id = 'PRR_three', pr_number = 99 } }

  local approved_pr
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.gh'] = {
      submit_review = function()
        error('should not submit a review belonging to another PR')
      end,
      approve_pr = function(number)
        approved_pr = number
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }, function()
    pr_commands.approve_pr():wait(1000)
  end)

  expect.equality(approved_pr, 12)
  state.pending_reviews = {}
end

return T
