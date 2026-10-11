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
  local old_filename = nil
  -- A deleted file has no new side, so its lines are numbered as in the old file.
  local is_deleted = false
  local current_line_in_file = 0
  -- Inside a hunk every line is content, even one starting with `---` or `+++`.
  local in_hunk = false

  --- @param header string `--- a/path` or `+++ b/path`
  --- @return string
  local function header_path(header)
    -- git ends the path with a tab when it contains spaces.
    return (header:match('^...%s*(.-)\t?$'):gsub('^[ab]/', ''))
  end

  for line_num = 1, #diff_content do
    local line = diff_content[line_num]

    if line:match('^diff ') then
      -- Header lines up to the first hunk belong to no file line.
      in_hunk = false
      current_filename = nil
      old_filename = nil
      is_deleted = false
    elseif line:sub(1, 2) == '@@' then
      in_hunk = true
      local pos = vim.split(line, ' ')[is_deleted and 2 or 3]
      local lineno = tonumber(vim.split(pos:sub(2), ',')[1])
      if lineno then
        current_line_in_file = lineno
      end
    elseif not in_hunk then
      if line:match('^%-%-%- ') then
        old_filename = header_path(line)
      elseif line:match('^%+%+%+ ') then
        local path = header_path(line)
        is_deleted = path == '/dev/null'
        if is_deleted then
          path = old_filename
        end
        current_filename = path and git_root .. '/' .. path
      end
    elseif current_filename then
      if filename_line_to_diff_line[current_filename] == nil then
        filename_line_to_diff_line[current_filename] = {}
      end
      filename_line_to_diff_line[current_filename][current_line_in_file] = line_num

      diff_line_to_filename_line[line_num] = { current_filename, current_line_in_file }
      if is_deleted or line:sub(1, 1) ~= '-' then
        current_line_in_file = current_line_in_file + 1
      end
    end
  end

  return filename_line_to_diff_line, diff_line_to_filename_line
end

return M
