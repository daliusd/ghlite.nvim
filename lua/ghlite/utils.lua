local M = {}

function M.system_str(cmd)
  local cmd_split = vim.fn.split(cmd, " ");
  local result = vim.system(cmd_split, { text = true }):wait()
  return vim.fn.split(result.stdout, '\n')
end

function M.system(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  return vim.fn.split(result.stdout, '\n')
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
  return M.system_str("git rev-parse --show-toplevel")[1]
end

function M.get_current_git_branch_name()
  return M.system_str('git branch --show-current')[1]
end

return M
