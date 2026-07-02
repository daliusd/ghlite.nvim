local async = require('async')
local ui = require('ghlite.ui')

local M = {}

--- Run an async function as a task, notifying the user on unhandled errors.
--- @param fn async fun()
--- @return vim.async.Task
function M.run(fn)
  local task = async.run(fn)
  task:on_complete(function(err)
    if err ~= nil then
      ui.notify('GHLite error: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end)
  return task
end

return M
