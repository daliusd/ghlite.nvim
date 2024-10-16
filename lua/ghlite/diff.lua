local utils = require "ghlite.utils"
local pr = require "ghlite.pr"
local config = require "ghlite.config"
local gh = require "ghlite.gh"

local M = {}

local function open_file_from_diff()
  local current_pr = gh.get_current_pr()
  if current_pr == nil then
    vim.notify('PR is not checked out', vim.log.levels.WARN)
    return
  end
  if pr.selected_PR ~= nil and current_pr ~= pr.selected_PR then
    vim.notify('Selected and Checked Out PRs mismatch.', vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local line_in_file = 0
  local line_in_file_found = false
  for line_num = cursor_line, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]

    if not line_in_file_found then
      if line:sub(1, 2) == '@@' then
        local pos = vim.split(line, ' ')[3]
        line_in_file = tonumber(vim.split(pos, ',')[1]) + line_in_file - 1
        line_in_file_found = true
      elseif line:sub(1, 1) ~= '-' then
        line_in_file = line_in_file + 1
      end
    end

    local file_path
    if line:match("^%-%-%-") then
      file_path = line:match("^%-%-%-%s*(.+)")
    elseif line:match("^+++") then
      file_path = line:match("^+++%s*(.+)")
    end

    if file_path then
      local git_root = utils.get_git_root()
      file_path = git_root .. '/' .. file_path:gsub("^a/", ""):gsub("^b/", "")
      vim.cmd("edit " .. file_path)
      vim.api.nvim_win_set_cursor(0, { line_in_file, 0 })
      return
    end
  end
end

function M.load_pr_diff()
  local pr_number = pr.get_selected_or_current_pr()
  if pr_number == nil then
    vim.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  vim.notify('PR diff loading started...')
  local diff_content = gh.get_pr_diff(pr_number)

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_content)

  vim.bo[buf].filetype = 'diff'

  if config.s.diff_split then
    vim.api.nvim_command(config.s.diff_split)
  end
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.open_file, '',
    { noremap = true, silent = true, callback = open_file_from_diff })
  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.approve, '',
    { noremap = true, silent = true, callback = pr.approve_pr })

  vim.notify('PR diff loaded.')
end

return M
