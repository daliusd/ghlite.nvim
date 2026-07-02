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
  return async.await(3, vim.ui.select, items, opts)
end

return M
