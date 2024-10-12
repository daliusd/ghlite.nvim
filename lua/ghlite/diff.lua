local utils = require "ghlite.utils"

local M = {}

local function open_file_from_diff()
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  for line_num = cursor_line, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]

    local file_path
    if line:match("^%-%-%-") then
      file_path = line:match("^%-%-%-%s*(.+)")
    elseif line:match("^+++") then
      file_path = line:match("^+++%s*(.+)")
    end

    if file_path then
      file_path = file_path:gsub("^a/", ""):gsub("^b/", "")
      vim.cmd("edit " .. file_path)
      return
    end
  end
end

function M.load_pr_diff()
  local diff_content = utils.readp('gh pr diff')

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_content)

  vim.bo[buf].filetype = 'diff'

  vim.api.nvim_command('vsplit')
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_set_keymap(buf, 'n', 'gf', '', { noremap = true, silent = true, callback = open_file_from_diff })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':bwipeout<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bwipeout<CR>', { noremap = true, silent = true })
end

return M