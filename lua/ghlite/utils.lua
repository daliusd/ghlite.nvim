local Job = require 'plenary.job'

local M = {}

function M.readp(cmd)
  local cmd_split = vim.fn.split(cmd, " ");
  local command = cmd_split[1]
  table.remove(cmd_split, 1)

  local job = Job:new({
    command = command,
    args = cmd_split,
    cwd = vim.fn.getcwd(),
  })

  job:sync()

  if job == nil then
    return {}
  end

  return job:result()
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

function M.split_by_newline(str)
  return vim.fn.split(str, '\n')
end

function M.get_git_root()
  return M.readp("git rev-parse --show-toplevel")[1]
end

return M
