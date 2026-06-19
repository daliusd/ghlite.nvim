local comments = require('ghlite.comments')
local config = require('ghlite.config')
local diff_utils = require('ghlite.diff_utils')
local gh = require('ghlite.gh')
local pr_commands = require('ghlite.pr_commands')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local utils = require('ghlite.utils')

local M = {}

--- @param cmd string
--- @return boolean
local function is_command_available(cmd)
  return vim.fn.exists(':' .. cmd) == 2
end

--- @return string|nil
local function get_diff_tool()
  return diff_utils.get_diff_tool(config.s.diff_tool, is_command_available)
end

local function construct_mappings(diff_content, cb)
  utils.get_git_root(function(git_root)
    state.filename_line_to_diff_line, state.diff_line_to_filename_line =
      diff_utils.construct_mappings(diff_content, git_root)
    cb()
  end)
end

local function open_file_from_diff(open_command)
  return function()
    pr_utils.get_checked_out_pr(function(checked_out_pr)
      if checked_out_pr == nil then
        utils.notify('No PR to work with.', vim.log.levels.WARN)
        return
      end

      vim.schedule(function()
        local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

        local fnpair = state.diff_line_to_filename_line[cursor_line]
        local file_path = fnpair[1]
        local line_in_file = fnpair[2]
        vim.cmd(open_command .. ' ' .. file_path)
        vim.api.nvim_win_set_cursor(0, { line_in_file, 0 })
      end)
    end)
  end
end

function M.load_pr_diff()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    utils.notify('PR diff loading started...')
    gh.get_pr_diff(selected_pr.number, function(diff_content)
      local diff_content_lines = vim.split(diff_content, '\n')
      construct_mappings(diff_content_lines, function()
        vim.schedule(function()
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_name(
            buf,
            'PR Diff: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')'
          )
          state.diff_buffer_id = buf

          vim.bo[buf].buftype = 'nofile'

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_content_lines)

          vim.bo[buf].filetype = 'diff'

          if config.s.diff_split then
            vim.api.nvim_command(config.s.diff_split)
          end
          vim.api.nvim_set_current_buf(buf)

          vim.bo[buf].readonly = true
          vim.bo[buf].modifiable = false

          if not utils.is_empty(config.s.keymaps.diff.open_file) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.open_file,
              '',
              { noremap = true, silent = true, callback = open_file_from_diff('edit') }
            )
          end

          if not utils.is_empty(config.s.keymaps.diff.open_file_tab) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.open_file_tab,
              '',
              { noremap = true, silent = true, callback = open_file_from_diff('tabedit') }
            )
          end

          if not utils.is_empty(config.s.keymaps.diff.open_file_split) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.open_file_split,
              '',
              { noremap = true, silent = true, callback = open_file_from_diff('split') }
            )
          end

          if not utils.is_empty(config.s.keymaps.diff.open_file_vsplit) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.open_file_vsplit,
              '',
              { noremap = true, silent = true, callback = open_file_from_diff('vsplit') }
            )
          end

          if not utils.is_empty(config.s.keymaps.diff.approve) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.approve,
              '',
              { noremap = true, silent = true, callback = pr_commands.approve_pr }
            )
          end

          if not utils.is_empty(config.s.keymaps.diff.request_changes) then
            vim.api.nvim_buf_set_keymap(
              buf,
              'n',
              config.s.keymaps.diff.request_changes,
              '',
              { noremap = true, silent = true, callback = pr_commands.request_changes_pr }
            )
          end

          utils.notify('PR diff loaded.')
          utils.notify('Comments on diff load started...')
          comments.load_comments_only(selected_pr.number, function()
            comments.load_comments_on_diff_buffer(buf)
            utils.notify('Comments on diff loaded.')
          end)
        end)
      end)
    end)
  end)
end

function M.load_pr_diffview()
  local diff_tool = get_diff_tool()

  if diff_tool == nil then
    local configured = config.s.diff_tool
    if configured == 'auto' then
      utils.notify('No diff tool available. Install diffview.nvim or codediff.nvim', vim.log.levels.ERROR)
    elseif configured == 'diffview' then
      utils.notify('diffview.nvim is not installed', vim.log.levels.ERROR)
    elseif configured == 'codediff' then
      utils.notify('codediff.nvim is not installed', vim.log.levels.ERROR)
    end
    return
  end

  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR to work with.', vim.log.levels.WARN)
      return
    end

    utils.notify('Comments load started...')
    comments.load_comments_only(selected_pr.number, function()
      utils.notify('Comments loaded.')
      utils.get_git_merge_base(
        selected_pr.baseRefOid and selected_pr.baseRefOid or selected_pr.baseRefName,
        selected_pr.headRefOid,
        function(mergeBaseOid)
          pr_utils.is_pr_checked_out(function(is_checked_out)
            vim.schedule(function()
              if diff_tool == 'diffview' then
                vim.cmd(string.format('DiffviewOpen %s..%s', mergeBaseOid, selected_pr.headRefOid))
              elseif diff_tool == 'codediff' then
                if is_checked_out then
                  vim.cmd(string.format('CodeDiff %s', mergeBaseOid))
                else
                  vim.cmd(string.format('CodeDiff %s %s', mergeBaseOid, selected_pr.headRefOid))
                end
              end
            end)
          end)
        end
      )
    end)
  end)
end

return M
