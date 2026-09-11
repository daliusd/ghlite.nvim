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

--- The tick walks every window of the current tab page, so each test gets a fresh one.
local function in_new_tab(fn)
  vim.cmd('tabnew')
  local ok, err = pcall(fn)
  vim.cmd('tabclose')
  if not ok then
    error(err)
  end
end

T['tick skips the comment reload when a visible PR view already reloaded them'] = function()
  in_new_tab(function()
    local state = require('ghlite.state')
    local refresh = require('ghlite.refresh')
    state.comments_pr_number = 12

    local view_buf = vim.api.nvim_get_current_buf()

    local refreshed_bufs = {}
    local comment_reloads = {}
    local diagnostics_refreshed = false
    with_overrides({
      ['ghlite.pr_commands'] = {
        refresh_buffer = function(buf)
          table.insert(refreshed_bufs, buf)
          return buf == view_buf and 12 or nil
        end,
      },
      ['ghlite.comments'] = {
        load_comments_only = function(pr_number)
          table.insert(comment_reloads, pr_number)
        end,
        load_comments_on_visible_buffers = function()
          diagnostics_refreshed = true
        end,
      },
    }, function()
      refresh.tick():wait(1000)
    end)

    expect.equality(refreshed_bufs, { view_buf })
    expect.equality(comment_reloads, {})
    expect.equality(diagnostics_refreshed, true)
    state.comments_pr_number = nil
  end)
end

T['tick reloads comments for the checked out PR when no view covers it'] = function()
  in_new_tab(function()
    local state = require('ghlite.state')
    local refresh = require('ghlite.refresh')
    state.comments_pr_number = 7

    local comment_reloads = {}
    with_overrides({
      ['ghlite.pr_commands'] = {
        refresh_buffer = function()
          return nil
        end,
      },
      ['ghlite.comments'] = {
        load_comments_only = function(pr_number)
          table.insert(comment_reloads, pr_number)
        end,
        load_comments_on_visible_buffers = function() end,
      },
    }, function()
      refresh.tick():wait(1000)
    end)

    expect.equality(comment_reloads, { 7 })
    state.comments_pr_number = nil
  end)
end

T['tick does not overlap a tick that is still running'] = function()
  in_new_tab(function()
    local refresh = require('ghlite.refresh')
    local async = require('async')

    local release
    local second
    with_overrides({
      ['ghlite.pr_commands'] = {
        refresh_buffer = function()
          async.await(1, function(cb)
            release = cb
          end)
          return nil
        end,
      },
    }, function()
      local first = refresh.tick()
      second = refresh.tick()
      release()
      first:wait(1000)
    end)

    expect.equality(second, nil)
    expect.no_equality(refresh.tick(), nil)
  end)
end

return T
