-- Periodic background refresh of whatever GHLite surfaces are visible.

local comments = require('ghlite.comments')
local config = require('ghlite.config')
local pr_commands = require('ghlite.pr_commands')
local state = require('ghlite.state')
local task = require('ghlite.task')

local M = {}

local timer
local running = false

--- Refresh every PR list / PR view buffer in the current tab page, then the review
--- comments of the PR they belong to. Requests run serially, as GitHub asks.
--- @return vim.async.Task|nil nil when a previous tick is still running
function M.tick()
  if running then
    return nil
  end
  running = true

  local bufs = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    table.insert(bufs, vim.api.nvim_win_get_buf(win))
  end

  local job = task.run(function()
    local reloaded_comments = {}
    for _, buf in ipairs(bufs) do
      local pr_number = pr_commands.refresh_buffer(buf)
      if pr_number ~= nil then
        reloaded_comments[pr_number] = true
      end
    end

    local pr_number = state.comments_pr_number
    if pr_number ~= nil then
      if not reloaded_comments[pr_number] then
        comments.load_comments_only(pr_number)
      end
      comments.load_comments_on_visible_buffers()
    end
  end)
  job:on_complete(function()
    running = false
  end)
  return job
end

function M.setup()
  if timer ~= nil then
    timer:stop()
    timer:close()
    timer = nil
  end

  local interval = config.s.refresh_interval
  if type(interval) ~= 'number' or interval <= 0 then
    return
  end

  timer = vim.uv.new_timer()
  timer:start(interval * 1000, interval * 1000, vim.schedule_wrap(M.tick))
end

return M
