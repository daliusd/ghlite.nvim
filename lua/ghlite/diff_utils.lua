local M = {}

--- @param configured string
--- @param is_command_available fun(cmd: string): boolean
--- @return string|nil
function M.get_diff_tool(configured, is_command_available)
  if configured == 'diffview' then
    return 'diffview'
  elseif configured == 'codediff' then
    return 'codediff'
  end

  if is_command_available('DiffviewOpen') then
    return 'diffview'
  elseif is_command_available('CodeDiff') then
    return 'codediff'
  end

  return nil
end

--- @param diff_content string[]
--- @param git_root string
--- @return table<string, table<number, number>>, table<number, FileNameAndLinePair>
function M.construct_mappings(diff_content, git_root)
  --- @type table<string, table<number, number>>
  local filename_line_to_diff_line = {}
  --- @type table<number, FileNameAndLinePair>
  local diff_line_to_filename_line = {}
  local current_filename = nil
  local current_line_in_file = 0

  for line_num = 1, #diff_content do
    local line = diff_content[line_num]

    if line:match('^%-%-%-') then
      do
      end -- this shouldn't become line
    elseif line:match('^+++') then
      current_filename = line:match('^+++%s*(.+)')
      current_filename = git_root .. '/' .. current_filename:gsub('^b/', '')
    elseif line:sub(1, 2) == '@@' then
      local pos = vim.split(line, ' ')[3]
      local lineno = tonumber(vim.split(pos, ',')[1])
      if lineno then
        current_line_in_file = lineno
      end
    elseif current_filename then
      if filename_line_to_diff_line[current_filename] == nil then
        filename_line_to_diff_line[current_filename] = {}
      end
      filename_line_to_diff_line[current_filename][current_line_in_file] = line_num

      diff_line_to_filename_line[line_num] = { current_filename, current_line_in_file }
      if line:sub(1, 1) ~= '-' then
        current_line_in_file = current_line_in_file + 1
      end
    end
  end

  return filename_line_to_diff_line, diff_line_to_filename_line
end

return M
