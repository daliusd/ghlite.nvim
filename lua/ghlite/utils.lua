local M = {}

function M.readp(cmd)
  local result = {}
  local pfile = assert(io.popen(cmd))
  for lines in pfile:lines() do
    table.insert(result, lines)
  end
  pfile:close()

  return result
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
  return M.readp("git rev-parse --show-toplevel 2> /dev/null")[1]
end

return M
