-- Boundary module for UI effects.

local async = require('async')

local M = {}

--- Fire-and-forget notification; safe to call from any context.
--- @param message string
--- @param level integer|nil
function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level)
  end)
end

--- Suspend until the main loop is reached; call before using vim.api from a
--- fast event context.
--- @async
function M.schedule()
  async.await(1, vim.schedule)
end

local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

--- Notify a spinner with elapsed time, updating once a second until the
--- returned function is called. Used for commands that can take a long time.
---
--- The notification carries the options notifier plugins use to replace a
--- previous notification in place (`replace` for nvim-notify, `id` for
--- snacks.nvim and fidget.nvim), so with one installed this renders as a
--- single updating notification. The built-in `vim.notify` ignores them and
--- appends a message per update instead.
--- @param message string
--- @return fun(final_message: string|nil, level: integer|nil) stop
function M.progress(message)
  local timer = vim.uv.new_timer()
  local started_at = vim.uv.now()
  local frame = 0
  local stopped = false
  local record

  local function render(text, level)
    record = vim.notify(text, level, {
      title = 'GHLite',
      id = 'ghlite_progress',
      replace = record,
    })
  end

  local function tick()
    if stopped then
      return
    end
    frame = frame % #spinner_frames + 1
    local elapsed = math.floor((vim.uv.now() - started_at) / 1000)
    render(string.format('%s %s (%ds)', spinner_frames[frame], message, elapsed))
  end

  vim.schedule(tick)
  timer:start(1000, 1000, vim.schedule_wrap(tick))

  --- Stop the spinner, optionally replacing it with a final message.
  return function(final_message, level)
    if stopped then
      return
    end
    stopped = true
    timer:stop()
    timer:close()

    if final_message ~= nil then
      vim.schedule(function()
        render(final_message, level)
      end)
    end
  end
end

--- @async
--- @param message string
--- @param choices string
--- @param default integer
--- @return integer choice
function M.confirm(message, choices, default)
  M.schedule()
  return vim.fn.confirm(message, choices, default)
end

--- @async
--- @param items any[]
--- @param opts table
--- @return any|nil item
--- @return integer|nil idx
function M.select(items, opts)
  M.schedule()
  -- Some `vim.ui.select` implementations (for example snacks.nvim) need to
  -- be invoked through a wrapper for async.nvim to receive their callback.
  return async.await(3, function(select_items, select_opts, callback)
    vim.ui.select(select_items, select_opts, callback)
  end, items, opts)
end

return M
