local comments = require('ghlite.comments')
local commit_commands = require('ghlite.commit_commands')
local commit_utils = require('ghlite.commit_utils')
local config = require('ghlite.config')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local system = require('ghlite.system')
local task = require('ghlite.task')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

local M = {}

local pr_list_buffer
local pr_list_by_buffer = {}
local pr_view_loading = {}
--- Per PR view buffer: `commits` in PR order plus the line -> index map used by
--- the open-commit keymaps.
local pr_view_commits_by_buffer = {}
--- Per PR view buffer: PR/review comment body lines -> comment and optional review thread.
local pr_view_comments_by_buffer = {}

--- @type async fun()
local load_pr_view

--- @async
--- @return PullRequest|nil
local function ui_selectPR(prompt)
  ui.notify('Loading PR list...')
  local prs = gh.get_pr_list()
  if #prs == 0 then
    ui.notify('No PRs found. Make sure you have `gh` configured.', vim.log.levels.WARN)
    return nil
  end

  return ui.select(prs, {
    prompt = prompt,
    format_item = function(pr)
      local date = pr.createdAt:sub(1, 10)
      local draft = pr.isDraft and ' Draft' or ''
      local approved = pr.reviewDecision == 'APPROVED' and ' Approved' or ''

      local labels = ''
      for _, label in pairs(pr.labels) do
        labels = labels .. ', ' .. label.name
      end

      return string.format(
        '#%s: %s (%s, %s%s%s%s)',
        pr.number,
        pr.title,
        pr.author.login,
        date,
        draft,
        approved,
        labels
      )
    end,
  })
end

function M.select()
  return task.run(function()
    local pr = ui_selectPR('Select PR:')
    if pr ~= nil then
      state.selected_PR = pr
      load_pr_view()
    end
  end)
end

local function format_pr_list_item(pr)
  local title = pr.title or ''
  if #title > 80 then
    title = title:sub(1, 77) .. '...'
  end

  local status = pr.reviewDecision and pr.reviewDecision:gsub('_', ' ') or 'REVIEW REQUIRED'
  if status == '' then
    status = 'REVIEW REQUIRED'
  end
  if pr.isDraft then
    status = 'DRAFT • ' .. status
  end

  local author = pr.author and pr.author.login or 'unknown author'
  local created_at = pr.createdAt and pr.createdAt:sub(1, 10) or 'unknown'
  local updated_at = pr.updatedAt and pr.updatedAt:sub(1, 10) or 'unknown'

  local labels = {}
  for _, label in ipairs(pr.labels or {}) do
    table.insert(labels, label.name)
  end

  local status_line = '  Status: ' .. status
  if #labels > 0 then
    status_line = status_line .. ' • Labels: ' .. table.concat(labels, ', ')
  end

  local checks = commit_utils.format_pr_check_summary(pr.statusCheckRollup)
  if checks ~= nil then
    status_line = status_line .. ' • ' .. checks
  end

  return {
    string.format('#%d  %s', pr.number, title),
    '  Author: ' .. author,
    string.format('  Created: %s • Updated: %s', created_at, updated_at),
    status_line,
  }
end

local function get_pr_list_buffer()
  if pr_list_buffer ~= nil and vim.api.nvim_buf_is_valid(pr_list_buffer) then
    return pr_list_buffer
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'GHLite PR List')
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'ghlite-pr-list'

  vim.api.nvim_buf_set_keymap(buf, 'n', 'cs', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.open_pr_under_cursor(buf)
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.open_pr_under_cursor(buf)
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'co', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.checkout_pr_under_cursor(buf)
    end,
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
    noremap = true,
    silent = true,
    callback = M.list,
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      pr_list_by_buffer[buf] = nil
      vim.api.nvim_buf_delete(buf, { force = true })
      pr_list_buffer = nil
    end,
  })

  pr_list_buffer = buf
  return buf
end

--- Open the PR on the current list entry.
--- @param buf integer
function M.open_pr_under_cursor(buf)
  local pr = pr_list_by_buffer[buf] and pr_list_by_buffer[buf][vim.api.nvim_win_get_cursor(0)[1]]
  if pr == nil then
    ui.notify('No PR on the current line.', vim.log.levels.WARN)
    return
  end

  state.selected_PR = pr
  M.load_pr_view()
end

--- Check out and open the PR on the current list entry.
--- @param buf integer
function M.checkout_pr_under_cursor(buf)
  local pr = pr_list_by_buffer[buf] and pr_list_by_buffer[buf][vim.api.nvim_win_get_cursor(0)[1]]
  if pr == nil then
    ui.notify('No PR on the current line.', vim.log.levels.WARN)
    return
  end

  return task.run(function()
    state.selected_PR = pr
    ui.notify(string.format('Checking out PR #%d...', pr.number))
    gh.checkout_pr(pr.number)
    ui.notify('PR checked out.')
    load_pr_view()
  end)
end

--- Open the commit view for the commit on the current PR view line.
--- @param buf integer
function M.open_commit_under_cursor(buf)
  local view = pr_view_commits_by_buffer[buf]
  local index = view and view.index_by_line[vim.api.nvim_win_get_cursor(0)[1]]
  if index == nil then
    ui.notify('No commit on the current line.', vim.log.levels.WARN)
    return
  end

  commit_commands.open_commit(view.commits[index].oid, {
    pr_number = view.pr_number,
    commits = view.commits,
    index = index,
  })
end

--- Check out the PR currently shown in the PR view and reload it.
--- @param pr_number number
function M.checkout_pr_in_view(pr_number)
  return task.run(function()
    ui.notify(string.format('Checking out PR #%d...', pr_number))
    gh.checkout_pr(pr_number)
    ui.notify('PR checked out.')
    load_pr_view()
  end)
end

function M.list()
  return task.run(function()
    ui.notify('Loading PR list...')
    local prs = gh.get_pr_list()

    ui.schedule()
    local buf = get_pr_list_buffer()
    local list_win = vim.fn.bufwinid(buf)
    if list_win ~= -1 then
      vim.api.nvim_set_current_win(list_win)
    else
      if not utils.is_empty(config.s.view_split) then
        vim.api.nvim_command(config.s.view_split)
      end
      vim.api.nvim_set_current_buf(buf)
    end

    local lines = { 'Pull requests', '', 'cs/<CR>: open   co: checkout and open   r: refresh   q: close', '' }
    local prs_by_line = {}
    if #prs == 0 then
      table.insert(lines, 'No open pull requests found.')
    else
      for _, pr in ipairs(prs) do
        for _, line in ipairs(format_pr_list_item(pr)) do
          table.insert(lines, line)
          prs_by_line[#lines] = pr
        end
        table.insert(lines, '')
      end
    end

    pr_list_by_buffer[buf] = prs_by_line
    vim.bo[buf].readonly = false
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false
  end)
end

function M.checkout()
  return task.run(function()
    local pr = ui_selectPR('Select PR to checkout:')
    if pr ~= nil then
      state.selected_PR = pr
      gh.checkout_pr(state.selected_PR.number)
      load_pr_view()
    end
  end)
end

--- Run a user-configured command against the PR view's PR and open its
--- output in a new buffer.
--- @param pr_number integer
--- @param entry table `name`, `cmd`
local function run_pr_command(pr_number, entry)
  return task.run(function()
    -- The command runs in the repo and relies on the PR branch being checked
    -- out, so make the reason explicit instead of silently doing nothing.
    local checked_out_pr, declined = pr_utils.get_checked_out_pr()
    if checked_out_pr == nil then
      if declined == nil then
        ui.notify('No PR to work with.', vim.log.levels.WARN)
      else
        ui.notify(string.format('"%s" not run: PR must be checked out.', entry.name), vim.log.levels.WARN)
      end
      return
    end

    local git_root = utils.get_git_root()

    -- Commands can run for minutes, so keep a spinner up until it finishes.
    local stop_progress = ui.progress(string.format('Running "%s"', entry.name))
    local ok, stdout, stderr = pcall(system.run_shell, entry.cmd, { cwd = git_root })

    if not ok then
      stop_progress(string.format('"%s" failed.', entry.name), vim.log.levels.ERROR)
      error(stdout, 0)
    end
    stop_progress(string.format('"%s" finished.', entry.name))

    ui.schedule()
    local output = stdout
    if utils.is_empty(output) and not utils.is_empty(stderr) then
      output = stderr
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(
      buf,
      string.format('PR #%d: %s (%s)', pr_number, entry.name, os.date('%Y-%m-%d %H:%M:%S'))
    )
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, '\n'))

    if config.s.view_split then
      vim.api.nvim_command(config.s.view_split)
    end
    vim.api.nvim_set_current_buf(buf)

    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false
  end)
end

local function format_pr_keymaps(is_checked_out)
  local keymaps = {
    { config.s.keymaps.pr.approve, 'approve PR' },
    { config.s.keymaps.pr.request_changes, 'request PR changes' },
    { config.s.keymaps.pr.merge, 'merge PR' },
    { config.s.keymaps.pr.comment, 'comment on PR' },
    { config.s.keymaps.comment.resolve, 'resolve comment thread' },
    { config.s.keymaps.comment.unresolve, 'unresolve comment thread' },
    { config.s.keymaps.pr.diff, 'open PR diff' },
    { config.s.keymaps.pr.diffview, 'open PR in diff tool' },
    { config.s.keymaps.pr.open_commit, 'open commit under cursor' },
    { config.s.keymaps.pr.refresh, 'refresh PR' },
  }
  if not is_checked_out then
    table.insert(keymaps, { config.s.keymaps.pr.checkout, 'checkout PR' })
  end
  for _, entry in ipairs(config.s.pr_commands or {}) do
    table.insert(keymaps, { entry.key, entry.name })
  end
  local hints = {}

  for _, keymap in ipairs(keymaps) do
    if not utils.is_empty(keymap[1]) then
      table.insert(hints, keymap[1] .. ': ' .. keymap[2])
    end
  end

  return table.concat(hints, '   ')
end

local function format_review_comments_for_pr_view()
  local review_section = {}
  local review_comments_by_line = {}

  if state.comments_list and next(state.comments_list) then
    table.insert(review_section, '')
    table.insert(review_section, '## Review Comments')
    table.insert(review_section, '')

    local filenames = {}
    for filename in pairs(state.comments_list) do
      table.insert(filenames, filename)
    end
    table.sort(filenames)

    for _, filename in pairs(filenames) do
      local comments_in_file = state.comments_list[filename]

      table.sort(comments_in_file, function(a, b)
        return a.line < b.line
      end)

      for _, comment_group in pairs(comments_in_file) do
        if #comment_group.comments > 0 then
          local outdated_suffix = comment_group.outdated and ' [outdated]' or ''
          local resolution_suffix = comment_group.resolved and ' [resolved]' or ' [unresolved]'
          local relative_filename = vim.fn.fnamemodify(filename, ':.')
          table.insert(
            review_section,
            string.format('### %s:%d%s%s', relative_filename, comment_group.line, outdated_suffix, resolution_suffix)
          )
          table.insert(review_section, '')

          for _, comment in pairs(comment_group.comments) do
            local comment_body = string.gsub(comment.body, '\r', '')
            local comment_lines = vim.split(comment_body, '\n')

            if comment == comment_group.comments[1] then
              table.insert(review_section, string.format('✍️ %s at %s:', comment.user, comment.updated_at))
            else
              table.insert(review_section, string.format('✍️ %s replied at %s:', comment.user, comment.updated_at))
            end

            for _, line in ipairs(comment_lines) do
              table.insert(review_section, line)
              review_comments_by_line[#review_section] = { group = comment_group, comment = comment }
            end
            table.insert(review_section, '')
          end
        end
      end
    end
  end

  return review_section, review_comments_by_line
end

local changed_file_statuses = {
  added = 'A',
  changed = 'M',
  copied = 'C',
  modified = 'M',
  removed = 'D',
  renamed = 'R',
}

local function format_changed_files(changed_files, total)
  local lines = { '', '## Changed files', '' }

  if changed_files == nil then
    table.insert(lines, '    Unable to load changed files.')
    return lines
  end

  for _, file in ipairs(changed_files) do
    table.insert(lines, string.format('    %s %s', changed_file_statuses[file.status] or '?', file.filename))
  end

  local remaining = total - #changed_files
  if remaining > 0 then
    table.insert(lines, string.format('    ... and %d more file%s.', remaining, remaining == 1 and '' or 's'))
  end

  return lines
end

--- @async
local function show_pr_info(pr_info)
  if pr_info == nil then
    ui.notify('PR view load failed', vim.log.levels.ERROR)
    return
  end

  local changed_files = gh.get_changed_files(pr_info.number)
  local current_branch = utils.get_current_git_branch_name()
  local is_checked_out = pr_info.headRefName ~= nil and pr_info.headRefName == current_branch
  comments.load_comments_only(pr_info.number)

  ui.schedule()
  local pr_view = {
    string.format('#%d %s', pr_info.number, pr_info.title),
    string.format('Created by %s at %s', pr_info.author.login, pr_info.createdAt),
    string.format('URL: %s', pr_info.url),
    string.format('Branch: %s%s', pr_info.headRefName or 'unknown', is_checked_out and ' (checked out)' or ''),
    string.format('Changed files: %d', pr_info.changedFiles),
  }

  if pr_info.isDraft then
    table.insert(pr_view, 'Draft')
  end

  if #pr_info.labels > 0 then
    local labels = 'Labels: '
    for idx, label in pairs(pr_info.labels) do
      labels = labels .. (idx > 1 and ', ' or '') .. label.name
    end
    table.insert(pr_view, labels)
  end

  if #pr_info.reviews > 0 then
    local reviews = 'Reviews: '
    for idx, review in pairs(pr_info.reviews) do
      reviews = reviews .. (idx > 1 and ', ' or '') .. string.format('%s (%s)', review.author.login, review.state)
    end
    table.insert(pr_view, reviews)
  end

  local keymap_hints = format_pr_keymaps(is_checked_out)
  if keymap_hints ~= '' then
    table.insert(pr_view, '')
    table.insert(pr_view, keymap_hints)
  end

  table.insert(pr_view, '')
  local body = string.gsub(pr_info.body, '\r', '')
  for _, line in ipairs(vim.split(body, '\n')) do
    table.insert(pr_view, line)
  end

  for _, line in ipairs(commit_utils.format_pr_checks(pr_info.statusCheckRollup)) do
    table.insert(pr_view, line)
  end

  local commits_offset = #pr_view
  local commit_lines, commit_index_by_line = commit_utils.format_commits(pr_info.commits)
  for _, line in ipairs(commit_lines) do
    table.insert(pr_view, line)
  end

  local commit_index_by_buffer_line = {}
  for line, index in pairs(commit_index_by_line) do
    commit_index_by_buffer_line[commits_offset + line] = index
  end

  for _, line in ipairs(format_changed_files(changed_files, pr_info.changedFiles)) do
    table.insert(pr_view, line)
  end

  local pr_comments_by_line = {}
  if #pr_info.comments > 0 then
    table.insert(pr_view, '')
    table.insert(pr_view, '## Comments')
    table.insert(pr_view, '')

    for _, comment in pairs(pr_info.comments) do
      table.insert(pr_view, string.format('✍️ %s at %s:', comment.author.login, comment.createdAt))

      local comment_body = string.gsub(comment.body, '\r', '')

      -- NOTE: naive check if it is HTML comment
      if config.s.html_comments_command ~= false and comment.body:match('<%s*[%w%-]+.-%s*>') ~= nil then
        local success, result = pcall(function()
          return system.run_sync(config.s.html_comments_command, { stdin = comment.body })
        end)
        if success then
          comment_body = result.stdout
        end
      end

      for _, line in ipairs(vim.split(comment_body, '\n')) do
        table.insert(pr_view, line)
        pr_comments_by_line[#pr_view] = { comment = comment }
      end
      table.insert(pr_view, '')
    end
  end

  local review_section, review_comments_by_line = format_review_comments_for_pr_view()
  local review_section_offset = #pr_view
  if #review_section > 0 then
    for _, line in ipairs(review_section) do
      table.insert(pr_view, line)
    end
    table.insert(pr_view, '')
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'PR View: ' .. pr_info.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')')

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pr_view)

  pr_view_commits_by_buffer[buf] = {
    pr_number = pr_info.number,
    commits = pr_info.commits or {},
    index_by_line = commit_index_by_buffer_line,
  }
  pr_view_comments_by_buffer[buf] = pr_comments_by_line
  for line, review_comment in pairs(review_comments_by_line) do
    pr_view_comments_by_buffer[buf][review_section_offset + line] = review_comment
  end

  if config.s.view_split then
    vim.api.nvim_command(config.s.view_split)
  end
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  if not utils.is_empty(config.s.keymaps.pr.approve) then
    vim.api.nvim_buf_set_keymap(
      buf,
      'n',
      config.s.keymaps.pr.approve,
      '',
      { noremap = true, silent = true, callback = M.approve_pr }
    )
  end
  if not utils.is_empty(config.s.keymaps.pr.request_changes) then
    vim.api.nvim_buf_set_keymap(
      buf,
      'n',
      config.s.keymaps.pr.request_changes,
      '',
      { noremap = true, silent = true, callback = M.request_changes_pr }
    )
  end
  if not utils.is_empty(config.s.keymaps.pr.merge) then
    vim.api.nvim_buf_set_keymap(
      buf,
      'n',
      config.s.keymaps.pr.merge,
      '',
      { noremap = true, silent = true, callback = M.merge_pr }
    )
  end
  if not utils.is_empty(config.s.keymaps.pr.comment) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.comment, '', {
      noremap = true,
      silent = true,
      callback = function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local comment = pr_view_comments_by_buffer[buf][line]
        if comment ~= nil then
          M.comment_on_pr(M.load_pr_view, comment.group, comment.comment)
        else
          M.comment_on_pr(M.load_pr_view)
        end
      end,
    })
  end
  local function set_thread_resolution(resolved)
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local entry = pr_view_comments_by_buffer[buf][line]
    if entry == nil or entry.group == nil then
      ui.notify('No review comment thread found on this line.', vim.log.levels.WARN)
      return
    end
    comments.set_conversation_resolved(entry.group, resolved, M.load_pr_view)
  end
  if not utils.is_empty(config.s.keymaps.comment.resolve) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.resolve, '', {
      noremap = true,
      silent = true,
      callback = function()
        set_thread_resolution(true)
      end,
    })
  end
  if not utils.is_empty(config.s.keymaps.comment.unresolve) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.unresolve, '', {
      noremap = true,
      silent = true,
      callback = function()
        set_thread_resolution(false)
      end,
    })
  end
  if not utils.is_empty(config.s.keymaps.pr.diff) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.diff, ':GHLitePRDiff<cr>', {
      noremap = true,
      silent = true,
    })
  end
  if not utils.is_empty(config.s.keymaps.pr.diffview) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.diffview, ':GHLitePRDiffview<cr>', {
      noremap = true,
      silent = true,
    })
  end
  if not is_checked_out and not utils.is_empty(config.s.keymaps.pr.checkout) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.checkout, '', {
      noremap = true,
      silent = true,
      callback = function()
        M.checkout_pr_in_view(pr_info.number)
      end,
    })
  end
  if not utils.is_empty(config.s.keymaps.pr.refresh) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.refresh, '', {
      noremap = true,
      silent = true,
      callback = M.load_pr_view,
    })
  end
  for _, entry in ipairs(config.s.pr_commands or {}) do
    if not utils.is_empty(entry.key) then
      vim.api.nvim_buf_set_keymap(buf, 'n', entry.key, '', {
        noremap = true,
        silent = true,
        callback = function()
          run_pr_command(pr_info.number, entry)
        end,
      })
    end
  end

  local function open_commit_under_cursor()
    M.open_commit_under_cursor(buf)
  end
  if not utils.is_empty(config.s.keymaps.pr.open_commit) then
    vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.open_commit, '', {
      noremap = true,
      silent = true,
      callback = open_commit_under_cursor,
    })
  end
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = open_commit_under_cursor,
  })

  ui.notify('PR view loaded.')
end

--- @async
load_pr_view = function()
  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    ui.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  if pr_view_loading[selected_pr.number] then
    ui.notify(string.format('PR #%d is already loading...', selected_pr.number), vim.log.levels.WARN)
    return
  end
  pr_view_loading[selected_pr.number] = true

  ui.notify('PR view loading started...')

  local ok, err = pcall(function()
    show_pr_info(gh.get_pr_info(selected_pr.number))
  end)

  pr_view_loading[selected_pr.number] = nil

  if not ok then
    error(err, 0)
  end
end

function M.load_pr_view()
  return task.run(load_pr_view)
end

M.comment_on_pr = function(on_success, comment_group, comment)
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    ui.schedule()
    local is_reply = comment_group ~= nil
    local prompt = '<!-- Type your PR comment and press ' .. config.s.keymaps.comment.send_comment .. ' to comment: -->'
    local content = { prompt, '' }
    if comment ~= nil then
      content = vim.list_extend(
        { prompt },
        vim.tbl_map(function(line)
          return '> ' .. line
        end, vim.split(comment.body, '\n'))
      )
    end

    utils.get_comment(
      'PR Comment: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
      config.s.comment_split,
      prompt,
      content,
      config.s.keymaps.comment.send_comment,
      function(input)
        task.run(function()
          if is_reply then
            comments.reply_to_comment(selected_pr.number, input, comment_group, on_success)
            return
          end

          ui.notify('Sending comment...')
          local resp = gh.new_pr_comment(state.selected_PR, input)
          if resp ~= nil then
            ui.notify('Comment sent.')
            if type(on_success) == 'function' then
              on_success()
            end
          else
            ui.notify('Failed to send comment.', vim.log.levels.WARN)
          end
        end)
      end
    )
  end)
end

--- @async
--- @param review PendingReview
--- @param event 'APPROVE'|'REQUEST_CHANGES'|'COMMENT'
--- @param body string|nil
local function submit_pending_review(review, event, body)
  ui.notify('Review submit started...')
  if gh.submit_review(review, event, body) == nil then
    ui.notify('Failed to submit review.', vim.log.levels.ERROR)
    return
  end
  state.pending_review = nil
  ui.notify('Review submitted.')
end

function M.start_review()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to review', vim.log.levels.ERROR)
      return
    end
    if pr_utils.active_pending_review(selected_pr.number) ~= nil then
      ui.notify('Review already started.', vim.log.levels.WARN)
      return
    end

    -- GitHub allows one pending review per PR, so adopt a review left over from an
    -- earlier session or started in the web UI instead of failing to create a second.
    local review = gh.get_pending_review(selected_pr.number) or gh.start_review(selected_pr.number)
    if review == nil then
      ui.notify('Failed to start review.', vim.log.levels.ERROR)
      return
    end

    state.pending_review = review
    ui.notify('Review started. Comments are held until :GHLitePRSubmitReview.')
  end)
end

function M.submit_review()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to review', vim.log.levels.ERROR)
      return
    end

    local review = pr_utils.active_pending_review(selected_pr.number)
    if review == nil then
      ui.notify('No review started. Use :GHLitePRStartReview.', vim.log.levels.WARN)
      return
    end

    local event = ui.select({ 'COMMENT', 'APPROVE', 'REQUEST_CHANGES' }, { prompt = 'Submit review as:' })
    if event == nil then
      return
    end
    if event == 'APPROVE' then
      submit_pending_review(review, event)
      return
    end

    -- GitHub requires a body for every event except APPROVE.
    ui.schedule()
    local prompt = '<!-- Type your review summary and press '
      .. config.s.keymaps.comment.send_comment
      .. ' to submit the review: -->'

    utils.get_comment(
      'PR Review Submit: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
      config.s.comment_split,
      prompt,
      { prompt, '' },
      config.s.keymaps.comment.send_comment,
      function(input)
        task.run(function()
          submit_pending_review(review, event, input)
        end)
      end
    )
  end)
end

function M.discard_review()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to review', vim.log.levels.ERROR)
      return
    end

    local review = pr_utils.active_pending_review(selected_pr.number)
    if review == nil then
      ui.notify('No review started.', vim.log.levels.WARN)
      return
    end

    ui.notify('Review discard started...')
    if not gh.discard_review(review) then
      ui.notify('Failed to discard review.', vim.log.levels.ERROR)
      return
    end
    state.pending_review = nil
    ui.notify('Review discarded.')
  end)
end

function M.approve_pr()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to approve', vim.log.levels.ERROR)
      return
    end

    local review = pr_utils.active_pending_review(selected_pr.number)
    if review ~= nil then
      submit_pending_review(review, 'APPROVE')
      return
    end

    ui.notify('PR approve started...')
    gh.approve_pr(selected_pr.number)
    ui.notify('PR approve finished.')
  end)
end

function M.request_changes_pr()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to request changes', vim.log.levels.ERROR)
      return
    end

    ui.schedule()
    local prompt = '<!-- Type your comment and press '
      .. config.s.keymaps.comment.send_comment
      .. ' to request PR changes: -->'

    utils.get_comment(
      'PR Request Changes: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
      config.s.comment_split,
      prompt,
      { prompt, '' },
      config.s.keymaps.comment.send_comment,
      function(input)
        task.run(function()
          local review = pr_utils.active_pending_review(selected_pr.number)
          if review ~= nil then
            submit_pending_review(review, 'REQUEST_CHANGES', input)
            return
          end

          ui.notify('PR request changes started...')
          gh.request_changes_pr(selected_pr.number, input)
          ui.notify('PR request changes finished.')
        end)
      end
    )
  end)
end

function M.merge_pr()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected to merge', vim.log.levels.ERROR)
      return
    end

    ui.notify('PR merge started...')
    if selected_pr.reviewDecision == 'APPROVED' then
      gh.merge_pr(selected_pr.number, config.s.merge.approved)
    else
      gh.merge_pr(selected_pr.number, config.s.merge.nonapproved)
    end
    ui.notify('PR merge finished.')
  end)
end

return M
