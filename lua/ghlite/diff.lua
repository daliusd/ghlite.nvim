local agent = require('ghlite.agent')
local comments = require('ghlite.comments')
local config = require('ghlite.config')
local diff_utils = require('ghlite.diff_utils')
local gh = require('ghlite.gh')
local pr_commands = require('ghlite.pr_commands')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local task = require('ghlite.task')
local ui = require('ghlite.ui')
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

--- @async
local function construct_mappings(diff_content)
  local git_root = utils.get_git_root()
  state.filename_line_to_diff_line, state.diff_line_to_filename_line =
    diff_utils.construct_mappings(diff_content, git_root)
end

local function open_file_from_diff(open_command)
  return function()
    task.run(function()
      -- Local changes are already in the working tree; a PR diff needs the PR checked out.
      if not state.diff_is_local then
        local checked_out_pr, declined = pr_utils.get_checked_out_pr()
        if checked_out_pr == nil then
          if declined == nil then
            ui.notify('No PR to work with.', vim.log.levels.WARN)
          end
          return
        end
      end

      ui.schedule()
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

      local fnpair = state.diff_line_to_filename_line[cursor_line]
      if fnpair == nil then
        ui.notify('No file line here; move to a line of a hunk.', vim.log.levels.WARN)
        return
      end
      local file_path = fnpair[1]
      local line_in_file = fnpair[2]
      -- Lines of a deleted file have nothing on disk to open.
      if vim.uv.fs_stat(file_path) == nil then
        ui.notify('File is not in the working tree.', vim.log.levels.WARN)
        return
      end
      vim.cmd(open_command .. ' ' .. vim.fn.fnameescape(file_path))
      vim.api.nvim_win_set_cursor(0, { line_in_file, 0 })
    end)
  end
end

--- Show diff output in the reusable diff view buffer, with its keymaps.
--- @async
--- @param name string buffer name, a timestamp is appended
--- @param diff_content_lines string[]
--- @param is_local boolean local changes rather than a PR: no PR actions
--- @return integer buf
local function open_diff_buffer(name, diff_content_lines, is_local)
  ui.schedule()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')')
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

  if not is_local and not utils.is_empty(config.s.keymaps.diff.approve) then
    vim.api.nvim_buf_set_keymap(
      buf,
      'n',
      config.s.keymaps.diff.approve,
      '',
      { noremap = true, silent = true, callback = pr_commands.approve_pr }
    )
  end

  if not is_local and not utils.is_empty(config.s.keymaps.diff.request_changes) then
    vim.api.nvim_buf_set_keymap(
      buf,
      'n',
      config.s.keymaps.diff.request_changes,
      '',
      { noremap = true, silent = true, callback = pr_commands.request_changes_pr }
    )
  end
  if not utils.is_empty(config.s.keymaps.comment.resolve) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.resolve, '', {
      noremap = true,
      silent = true,
      callback = comments.resolve_comment,
    })
  end
  if not utils.is_empty(config.s.keymaps.comment.unresolve) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.unresolve, '', {
      noremap = true,
      silent = true,
      callback = comments.unresolve_comment,
    })
  end

  return buf
end

--- Show the local changes an agent review covers when no PR is selected.
--- @async
local function load_local_diff()
  local scope = agent.resolve_scope()
  if scope == nil then
    ui.notify('No commits to compare local changes with.', vim.log.levels.ERROR)
    return
  end

  ui.notify('Local diff loading started...')
  local diff_content = agent.get_local_diff(scope)
  if vim.trim(diff_content or '') == '' then
    ui.notify('No local changes against ' .. scope.base .. '.', vim.log.levels.WARN)
    return
  end
  local diff_content_lines = vim.split(diff_content, '\n')
  construct_mappings(diff_content_lines)
  state.diff_is_local = true

  local buf = open_diff_buffer('Local Diff: ' .. scope.base, diff_content_lines, true)
  comments.load_comments_on_diff_buffer(buf)
  ui.notify('Local diff loaded.')
end

function M.load_pr_diff()
  return task.run(function()
    -- Without a PR an agent review covers the local changes, so look one up quietly.
    local has_agent_review = agent.get(agent.root()) ~= nil
    local selected_pr = pr_utils.get_selected_pr(has_agent_review)
    if selected_pr == nil then
      if has_agent_review then
        load_local_diff()
        return
      end
      ui.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    ui.notify('PR diff loading started...')
    local diff_content = gh.get_pr_diff(selected_pr.number)
    local diff_content_lines = vim.split(diff_content, '\n')
    construct_mappings(diff_content_lines)
    state.diff_is_local = false

    local buf = open_diff_buffer('PR Diff: ' .. selected_pr.number, diff_content_lines, false)

    ui.notify('PR diff loaded.')
    ui.notify('Comments on diff load started...')
    comments.load_comments_only(selected_pr.number)
    comments.load_comments_on_diff_buffer(buf)
    ui.notify('Comments on diff loaded.')
  end)
end

function M.load_pr_diffview()
  local diff_tool = get_diff_tool()

  if diff_tool == nil then
    local configured = config.s.diff_tool
    if configured == 'auto' then
      ui.notify('No diff tool available. Install diffview.nvim or codediff.nvim', vim.log.levels.ERROR)
    elseif configured == 'diffview' then
      ui.notify('diffview.nvim is not installed', vim.log.levels.ERROR)
    elseif configured == 'codediff' then
      ui.notify('codediff.nvim is not installed', vim.log.levels.ERROR)
    end
    return
  end

  return task.run(function()
    local has_agent_review = agent.get(agent.root()) ~= nil
    local selected_pr = pr_utils.get_selected_pr(has_agent_review)
    if selected_pr == nil then
      if not has_agent_review then
        ui.notify('No PR to work with.', vim.log.levels.WARN)
        return
      end
      -- The working tree against the merge base: the local changes an agent review covers.
      local scope = agent.resolve_scope()
      if scope == nil then
        ui.notify('No commits to compare local changes with.', vim.log.levels.ERROR)
        return
      end
      ui.schedule()
      vim.cmd(string.format('%s %s', diff_tool == 'diffview' and 'DiffviewOpen' or 'CodeDiff', scope.merge_base))
      return
    end

    ui.notify('Comments load started...')
    comments.load_comments_only(selected_pr.number)
    ui.notify('Comments loaded.')

    if not utils.ensure_pr_commits(selected_pr) then
      ui.notify('Unable to fetch the commits needed for this PR diff.', vim.log.levels.ERROR)
      return
    end

    local base_ref = selected_pr.baseRefOid or ('origin/' .. selected_pr.baseRefName)
    local mergeBaseOid = utils.get_git_merge_base(base_ref, selected_pr.headRefOid)
    if mergeBaseOid == nil or mergeBaseOid == '' then
      ui.notify('Unable to determine the merge base for this PR.', vim.log.levels.ERROR)
      return
    end

    local is_checked_out = pr_utils.is_pr_checked_out()

    ui.schedule()
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
end

return M
