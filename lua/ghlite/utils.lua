local config = require "ghlite.config"

local M = {}

function M.system_str_cb(cmd, cb)
  local cmd_split = vim.split(cmd, " ");
  vim.system(cmd_split, { text = true }, function(result)
    if type(cb) == "function" then
      if #result.stderr > 0 then
        config.log("system_str_cb error", result.stderr)
        M.notify(result.stderr, vim.log.levels.ERROR)
      end

      cb(result.stdout, result.stderr)
    end
  end)
end

function M.system_cb(cmd, cb)
  vim.system(cmd, { text = true }, function(result)
    if type(cb) == "function" then
      cb(result.stdout)
    end
  end)
end

function M.filter_array(arr, condition)
  local result = {}
  for _, v in ipairs(arr) do
    if condition(v) then
      table.insert(result, v)
    end
  end
  return result
end

function M.is_empty(value)
  if value == nil or vim.fn.empty(value) == 1 then
    return true
  end
  return false
end

function M.get_git_root(cb)
  M.system_str_cb("git rev-parse --show-toplevel", function(result)
    cb(vim.split(result, '\n')[1])
  end)
end

function M.get_current_git_branch_name(cb)
  M.system_str_cb('git branch --show-current', function(result)
    cb(vim.split(result, '\n')[1])
  end)
end

function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level)
  end)
end

return M
