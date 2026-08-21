local commit_utils = require('ghlite.commit_utils')
local config = require('ghlite.config')
local diff_utils = require('ghlite.diff_utils')
local gh = require('ghlite.gh')
local system = require('ghlite.system')
local task = require('ghlite.task')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

require('ghlite.types')

local M = {}

--- Per commit view buffer: the commit it shows, the commit list it was opened
--- from (for navigation) and the diff line mapping used to open files.
local commit_view_by_buffer = {}

--- @param cmd string
--- @return boolean
local function is_command_available(cmd)
  return vim.fn.exists(':' .. cmd) == 2
end

--- @param buf integer
--- @param open_command string
local function open_file_from_commit(buf, open_command)
  return function()
    local view = commit_view_by_buffer[buf]
    if view == nil then
      return
    end

    local fnpair = view.diff_line_to_filename_line[vim.api.nvim_win_get_cursor(0)[1]]
    if fnpair == nil then
      ui.notify('No diff line under the cursor.', vim.log.levels.WARN)
      return
    end

    -- Deleted files are diffed against /dev/null, so there is nothing to open.
    if commit_utils.is_dev_null(fnpair[1]) then
      ui.notify('File was deleted in this commit.', vim.log.levels.WARN)
      return
    end

    vim.cmd(open_command .. ' ' .. fnpair[1])

    -- The working tree may not hold the commit, so the line can be out of range.
    local line_count = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(fnpair[2], line_count)), 0 })
  end
end

--- @param buf integer
--- @param step number
local function open_neighbour_commit(buf, step)
  return function()
    local view = commit_view_by_buffer[buf]
    if view == nil or view.commits == nil then
      return
    end

    local index = (view.index or 0) + step
    if index < 1 or index > #view.commits then
      ui.notify(step > 0 and 'Last commit in the PR.' or 'First commit in the PR.', vim.log.levels.WARN)
      return
    end

    M.open_commit(view.commits[index].oid, {
      pr_number = view.pr_number,
      commits = view.commits,
      index = index,
    })
  end
end

--- @param buf integer
local function open_commit_diff(buf)
  return function()
    local view = commit_view_by_buffer[buf]
    if view == nil then
      return
    end

    if view.parent_sha == nil then
      ui.notify('Commit has no parent to diff against.', vim.log.levels.WARN)
      return
    end

    local diff_tool = diff_utils.get_diff_tool(config.s.diff_tool, is_command_available)
    if diff_tool == nil then
      ui.notify('No diff tool available. Install diffview.nvim or codediff.nvim', vim.log.levels.ERROR)
      return
    end

    if diff_tool == 'diffview' then
      vim.cmd(string.format('DiffviewOpen %s..%s', view.parent_sha, view.sha))
    elseif diff_tool == 'codediff' then
      vim.cmd(string.format('CodeDiff %s %s', view.parent_sha, view.sha))
    end
  end
end

--- @param buf integer
--- @param key string
--- @param callback function
local function set_keymap(buf, key, callback)
  if utils.is_empty(key) then
    return
  end
  vim.api.nvim_buf_set_keymap(buf, 'n', key, '', { noremap = true, silent = true, callback = callback })
end

--- @async
--- @param sha string
--- @param opts table
local function show_commit(sha, opts)
  local commit = gh.get_commit(sha)
  if commit == nil or commit.sha == nil then
    ui.notify(
      string.format(
        'Commit %s not found. It may have been force-pushed away; refresh the PR view.',
        commit_utils.short_sha(sha)
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local check_runs = gh.get_commit_checks(commit.sha)
  local git_root = utils.get_git_root()

  -- NOTE: formatting reads config through utils.is_empty, so it has to run on
  -- the main loop rather than in the fast event context we return to here.
  ui.schedule()

  local lines, unmappable_lines = commit_utils.format_commit_view(commit, check_runs, opts)
  local _, diff_line_to_filename_line = diff_utils.construct_mappings(lines, git_root)
  for _, line_num in ipairs(unmappable_lines) do
    diff_line_to_filename_line[line_num] = nil
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(
    buf,
    'Commit: ' .. commit_utils.short_sha(commit.sha) .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')'
  )

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  commit_view_by_buffer[buf] = {
    sha = commit.sha,
    parent_sha = commit.parents and commit.parents[1] and commit.parents[1].sha or nil,
    pr_number = opts.pr_number,
    commits = opts.commits,
    index = opts.index,
    diff_line_to_filename_line = diff_line_to_filename_line,
  }

  if config.s.view_split then
    vim.api.nvim_command(config.s.view_split)
  end
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  local keymaps = config.s.keymaps.commit

  set_keymap(buf, keymaps.open_file, open_file_from_commit(buf, 'edit'))
  set_keymap(buf, keymaps.open_file_split, open_file_from_commit(buf, 'split'))
  set_keymap(buf, keymaps.open_file_vsplit, open_file_from_commit(buf, 'vsplit'))
  set_keymap(buf, keymaps.diff, open_commit_diff(buf))
  set_keymap(buf, keymaps.next_commit, open_neighbour_commit(buf, 1))
  set_keymap(buf, keymaps.prev_commit, open_neighbour_commit(buf, -1))

  set_keymap(buf, keymaps.yank_sha, function()
    vim.fn.setreg('"', commit.sha)
    vim.fn.setreg('+', commit.sha)
    ui.notify('Copied ' .. commit.sha)
  end)

  set_keymap(buf, keymaps.open_in_browser, function()
    task.run(function()
      system.run({ config.s.open_command, commit.html_url })
    end)
  end)

  set_keymap(buf, keymaps.refresh, function()
    M.open_commit(sha, opts)
  end)

  set_keymap(buf, keymaps.close, function()
    commit_view_by_buffer[buf] = nil
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  ui.notify('Commit view loaded.')
end

--- Open the commit view for a SHA.
--- @param sha string
--- @param opts table|nil `pr_number`, `commits` and `index` for navigation
function M.open_commit(sha, opts)
  opts = opts or {}

  return task.run(function()
    ui.notify(string.format('Commit %s loading started...', commit_utils.short_sha(sha)))
    show_commit(sha, opts)
  end)
end

return M
