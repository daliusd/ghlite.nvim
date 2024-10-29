local utils = require "ghlite.utils"
local pr_commands = require "ghlite.pr_commands"
local config = require "ghlite.config"
local gh = require "ghlite.gh"
local comments = require "ghlite.comments"
local state = require "ghlite.state"
local pr_utils = require "ghlite.pr_utils"

local M = {}

local function construct_mappings(diff_content)
  local git_root = utils.get_git_root()
  local current_filename = nil
  local current_line_in_file = 0

  for line_num = 1, #diff_content do
    local line = diff_content[line_num]

    if line:match("^%-%-%-") then
      do end -- this shouldn't become line
    elseif line:match("^+++") then
      current_filename = line:match("^+++%s*(.+)")
      current_filename = git_root .. '/' .. current_filename:gsub("^b/", "")
    elseif line:sub(1, 2) == '@@' then
      local pos = vim.split(line, ' ')[3]
      local lineno = tonumber(vim.split(pos, ',')[1])
      if lineno then
        current_line_in_file = lineno
      end
    elseif current_filename then
      if state.filename_line_to_diff_line[current_filename] == nil then
        state.filename_line_to_diff_line[current_filename] = {}
      end
      state.filename_line_to_diff_line[current_filename][current_line_in_file] = line_num

      state.diff_line_to_filename_line[line_num] = { current_filename, current_line_in_file }
      if line:sub(1, 1) ~= '-' then
        current_line_in_file = current_line_in_file + 1
      end
    end
  end
end

local function open_file_from_diff(open_command)
  return function()
    if pr_utils.get_checked_out_pr() == nil then
      vim.notify('No PR to work with.', vim.log.levels.WARN)
      return
    end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    local fnpair = state.diff_line_to_filename_line[cursor_line]
    local file_path = fnpair[1]
    local line_in_file = fnpair[2]
    vim.cmd(open_command .. ' ' .. file_path)
    vim.api.nvim_win_set_cursor(0, { line_in_file, 0 })
  end
end

function M.load_pr_diff()
  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    vim.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  vim.notify('PR diff loading started...')
  local diff_content = gh.get_pr_diff(selected_pr.number)
  construct_mappings(diff_content)

  local buf = vim.api.nvim_create_buf(false, true)
  state.diff_buffer_id = buf

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
    { noremap = true, silent = true, callback = open_file_from_diff('edit') })
  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.open_file_tab, '',
    { noremap = true, silent = true, callback = open_file_from_diff('tabedit') })
  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.open_file_split, '',
    { noremap = true, silent = true, callback = open_file_from_diff('split') })
  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.open_file_vsplit, '',
    { noremap = true, silent = true, callback = open_file_from_diff('vsplit') })
  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.diff.approve, '',
    { noremap = true, silent = true, callback = pr_commands.approve_pr })

  vim.notify('PR diff loaded.')
  vim.notify('Comments on diff load started...')
  comments.load_comments_only(selected_pr.number)
  comments.load_comments_on_diff_buffer(buf)
  vim.notify('Comments on diff loaded.')
end

function M.load_pr_diffview()
  local checked_out_pr = pr_utils.get_checked_out_pr()
  if checked_out_pr == nil then
    vim.notify('No PR to work with.', vim.log.levels.WARN)
    return
  end

  vim.cmd(string.format('DiffviewOpen %s..HEAD', checked_out_pr.baseRefName))
end

return M
