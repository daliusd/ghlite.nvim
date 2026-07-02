local comments_utils = require('ghlite.comments_utils')
local config = require('ghlite.config')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local system = require('ghlite.system')
local task = require('ghlite.task')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

local M = {}

local function load_comments_to_quickfix_list()
  local qf_entries = {}

  local filenames = {}
  for fn in pairs(state.comments_list) do
    table.insert(filenames, fn)
  end
  table.sort(filenames)

  for _, filename in pairs(filenames) do
    local comments_in_file = state.comments_list[filename]

    table.sort(comments_in_file, function(a, b)
      return a.line < b.line
    end)

    for _, comment in pairs(comments_in_file) do
      if #comment.comments > 0 then
        table.insert(qf_entries, {
          filename = filename,
          lnum = comment.line,
          text = comment.content,
        })
      end
    end
  end

  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries, 'r')
    vim.cmd('cfirst')
  else
    ui.notify('No GH comments loaded.')
  end
end

M.load_comments = function()
  return task.run(function()
    local checked_out_pr, declined = pr_utils.get_checked_out_pr()
    if checked_out_pr == nil then
      if declined == nil then
        ui.notify('No PR to work with.', vim.log.levels.WARN)
      end
      return
    end

    ui.notify('Comment loading started...')
    state.comments_list = gh.load_comments(checked_out_pr.number)
    ui.schedule()
    load_comments_to_quickfix_list()

    M.load_comments_on_current_buffer()
    ui.notify('Comments loaded.')
  end)
end

--- @async
M.load_comments_only = function(pr_to_load)
  state.comments_list = gh.load_comments(pr_to_load)
end

M.load_comments_on_current_buffer = function()
  vim.schedule(function()
    local current_buffer = vim.api.nvim_get_current_buf()
    M.load_comments_on_buffer(current_buffer)
  end)
end

M.load_comments_on_buffer = function(bufnr)
  if bufnr == state.diff_buffer_id then
    M.load_comments_on_diff_buffer(bufnr)
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(bufnr)

  return task.run(function()
    if M.is_in_diffview(buf_name) then
      local filename = M.get_diffview_filename(buf_name)
      if filename then
        M.load_comments_on_buffer_by_filename(bufnr, filename)
      end
      return
    end

    -- Handle CodeDiff buffers
    if M.is_in_codediff(buf_name) then
      local filename = M.get_codediff_filename(buf_name)
      if filename then
        M.load_comments_on_buffer_by_filename(bufnr, filename)
      end
      return
    end

    if not pr_utils.is_pr_checked_out() then
      return
    end

    M.load_comments_on_buffer_by_filename(bufnr, buf_name)
  end)
end

M.load_comments_on_diff_buffer = function(bufnr)
  config.log('load_comments_on_diff_buffer')
  local diagnostics = {}

  for filename, comments in pairs(state.comments_list) do
    if state.filename_line_to_diff_line[filename] then
      for _, comment in pairs(comments) do
        local diff_line = state.filename_line_to_diff_line[filename][comment.line]
        if diff_line and #comment.comments > 0 then
          table.insert(diagnostics, {
            lnum = diff_line - 1,
            col = 0,
            message = comment.content,
            severity = vim.diagnostic.severity.INFO,
            source = 'GHLite',
          })
        end
      end
    end
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      config.log('load_comments_on_diff_buffer: buffer no longer valid', bufnr)
      return
    end
    vim.diagnostic.set(vim.api.nvim_create_namespace('GHLiteDiffNamespace'), bufnr, diagnostics, {})
  end)
end

M.get_conversations = function(current_filename, current_line)
  --- @type GroupedComment[]
  local conversations = {}
  if state.comments_list[current_filename] ~= nil then
    for _, comment in pairs(state.comments_list[current_filename]) do
      if current_line == comment.line then
        table.insert(conversations, comment)
      end
    end
  end
  return conversations
end

--- @async
--- @return string|nil filename
--- @return integer|nil start_line
--- @return integer|nil line
--- @return string|nil reason 'silent' when the caller should stay quiet
local function get_current_filename_and_line()
  ui.schedule()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_start_line = vim.fn.line("'<")
  local current_line = vim.fn.line("'>")

  if current_line == 0 then
    current_start_line = vim.api.nvim_win_get_cursor(0)[1]
    current_line = current_start_line
  end

  local current_filename = vim.api.nvim_buf_get_name(current_buf)

  if current_buf == state.diff_buffer_id then
    local info = state.diff_line_to_filename_line[current_start_line]
    current_filename = info[1]
    current_start_line = info[2]
    info = state.diff_line_to_filename_line[current_line]
    current_line = info[2]
    return current_filename, current_start_line, current_line
  elseif M.is_in_diffview(current_filename) then
    local filename = M.get_diffview_filename(current_filename)
    if filename == nil then
      return nil, nil, nil, 'silent'
    end
    return filename, current_start_line, current_line
  elseif M.is_in_codediff(current_filename) then
    local filename = M.get_codediff_filename(current_filename)
    if filename == nil then
      return nil
    end
    return filename, current_start_line, current_line
  else
    local is_pr_checked_out = pr_utils.is_pr_checked_out()
    local checked_out_pr, declined = pr_utils.get_checked_out_pr()
    if declined ~= nil then
      return nil, nil, nil, 'silent'
    end
    if not is_pr_checked_out then
      if checked_out_pr then
        ui.notify('Command canceled because of PR check out.', vim.log.levels.WARN)
      end
      return nil
    end
    return current_filename, current_start_line, current_line
  end
end

M.comment_on_line = function()
  return task.run(function()
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    local current_filename, current_start_line, current_line, reason = get_current_filename_and_line()
    if current_filename == nil or current_start_line == nil or current_line == nil then
      if reason ~= 'silent' then
        ui.notify('You are on a branch without PR.', vim.log.levels.WARN)
      end
      return
    end

    local git_root = utils.get_git_root()
    if current_filename:sub(1, #git_root) ~= git_root then
      ui.notify('File is not under git folder.', vim.log.levels.ERROR)
      return
    end

    ui.schedule()
    local conversations = {}
    if current_start_line == current_line then
      conversations = M.get_conversations(current_filename, current_line)
    end

    local prompt = '<!-- Type your '
      .. (#conversations > 0 and 'reply' or 'comment')
      .. ' and press '
      .. config.s.keymaps.comment.send_comment
      .. ': -->'

    utils.get_comment(
      (#conversations > 0 and 'PR reply' or 'PR comment') .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
      config.s.comment_split,
      prompt,
      { prompt, '' },
      config.s.keymaps.comment.send_comment,
      function(input)
        task.run(function()
          --- @async
          --- @param grouped_comment GroupedComment
          local function reply(grouped_comment)
            ui.notify('Sending reply...')
            local resp = gh.reply_to_comment(state.selected_PR.number, input, grouped_comment.id)
            if resp['errors'] == nil then
              ui.notify('Reply sent.')
              local new_comment = comments_utils.convert_comment(resp)
              table.insert(grouped_comment.comments, new_comment)
              grouped_comment.content = comments_utils.prepare_content(grouped_comment.comments)
              M.load_comments_on_current_buffer()
            else
              ui.notify('Failed to reply to comment.', vim.log.levels.WARN)
            end
          end

          if #conversations == 1 then
            reply(conversations[1])
          elseif #conversations > 1 then
            local comment = ui.select(conversations, {
              prompt = 'Select comment to reply to:',
              format_item = function(comment)
                return string.format('%s', vim.split(comment.content, '\n')[1])
              end,
            })
            if comment ~= nil then
              reply(comment)
            end
          else
            if current_filename:sub(1, #git_root) == git_root then
              ui.notify('Sending comment...')
              local resp = gh.new_comment(
                state.selected_PR,
                input,
                current_filename:sub(#git_root + 2),
                current_start_line,
                current_line
              )
              if resp['errors'] == nil then
                local new_comment = comments_utils.convert_comment(resp)
                --- @type GroupedComment
                local new_comment_group = {
                  id = resp.id,
                  line = current_line,
                  start_line = current_start_line,
                  url = resp.html_url,
                  comments = { new_comment },
                  content = comments_utils.prepare_content({ new_comment }),
                }
                if state.comments_list[current_filename] == nil then
                  state.comments_list[current_filename] = { new_comment_group }
                else
                  table.insert(state.comments_list[current_filename], new_comment_group)
                end

                ui.notify('Comment sent.')
                M.load_comments_on_current_buffer()
              else
                ui.notify('Failed to send comment.', vim.log.levels.WARN)
              end
            end
          end
        end)
      end
    )
  end)
end

M.open_comment = function()
  return task.run(function()
    local current_filename, _, current_line, reason = get_current_filename_and_line()
    if current_filename == nil then
      if reason ~= 'silent' then
        ui.notify('You are on a branch without PR.', vim.log.levels.WARN)
      end
      return
    end

    local conversations = M.get_conversations(current_filename, current_line)

    if #conversations == 1 then
      system.run({ config.s.open_command, conversations[1].url })
    elseif #conversations > 1 then
      local comment = ui.select(conversations, {
        prompt = 'Select conversation to open in browser:',
        format_item = function(comment)
          return string.format('%s', vim.split(comment.content, '\n')[1])
        end,
      })
      if comment ~= nil then
        system.run({ config.s.open_command, comment.url })
      end
    else
      ui.notify('No comments found on this line.', vim.log.levels.WARN)
    end
  end)
end

--- @async
local function get_own_comments(current_filename, current_line)
  local conversations = M.get_conversations(current_filename, current_line)
  local user = gh.get_user()

  --- @type Comment[]
  local comments_list = {}
  --- @type GroupedComment[]
  local conversations_list = {}

  for _, convo in pairs(conversations) do
    for _, comment in pairs(convo.comments) do
      if comment.user == user then
        table.insert(comments_list, comment)
        table.insert(conversations_list, convo)
      end
    end
  end

  return comments_list, conversations_list
end

--- @param comment Comment
--- @param conversation GroupedComment
local function edit_comment_body(comment, conversation)
  local prompt = '<!-- Change your comment and press ' .. config.s.keymaps.comment.send_comment .. ': -->'

  utils.get_comment(
    'PR edit comment' .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
    config.s.comment_split,
    prompt,
    vim.split(prompt .. '\n' .. comment.body, '\n'),
    config.s.keymaps.comment.send_comment,
    function(input)
      task.run(function()
        ui.notify('Updating comment...')
        local resp = gh.update_comment(comment.id, input)
        if resp['errors'] == nil then
          ui.notify('Comment updated.')
          comment.body = resp.body
          conversation.content = comments_utils.prepare_content(conversation.comments)

          M.load_comments_on_current_buffer()
        else
          ui.notify('Failed to update the comment.', vim.log.levels.ERROR)
        end
      end)
    end
  )
end

M.update_comment = function()
  return task.run(function()
    local current_filename, _, current_line, reason = get_current_filename_and_line()
    if current_filename == nil then
      if reason ~= 'silent' then
        ui.notify('You are on a branch without PR.', vim.log.levels.WARN)
      end
      return
    end

    local comments_list, conversations_list = get_own_comments(current_filename, current_line)
    if #comments_list == 0 then
      ui.notify('No comments found that could be updated.', vim.log.levels.WARN)
      return
    end

    local comment, idx = ui.select(comments_list, {
      prompt = 'Select comment to update:',
      format_item = function(comment)
        return string.format('%s: %s', comment.updated_at, vim.split(comment.body, '\n')[1])
      end,
    })
    if comment ~= nil then
      edit_comment_body(comment, conversations_list[idx])
    end
  end)
end

M.delete_comment = function()
  return task.run(function()
    local current_filename, _, current_line, reason = get_current_filename_and_line()
    if current_filename == nil then
      if reason ~= 'silent' then
        ui.notify('You are on a branch without PR.', vim.log.levels.WARN)
      end
      return
    end

    local comments_list, conversations_list = get_own_comments(current_filename, current_line)
    if #comments_list == 0 then
      ui.notify('No comments found that could be deleted.', vim.log.levels.WARN)
      return
    end

    local comment, idx = ui.select(comments_list, {
      prompt = 'Select comment to delete:',
      format_item = function(comment)
        return string.format('%s: %s', comment.updated_at, vim.split(comment.body, '\n')[1])
      end,
    })
    if comment ~= nil then
      ui.notify('Deleting comment...')
      gh.delete_comment(comment.id)

      local function is_non_deleted_comment(c)
        return c.id ~= comment.id
      end

      local convo = conversations_list[idx]
      convo.comments = utils.filter_array(convo.comments, is_non_deleted_comment)
      convo.content = comments_utils.prepare_content(convo.comments)

      ui.notify('Comment deleted.')
      M.load_comments_on_current_buffer()
    end
  end)
end

M.is_in_diffview = function(buf_name)
  return string.sub(buf_name, 1, 11) == 'diffview://'
end

M.is_in_codediff = function(buf_name)
  return string.sub(buf_name, 1, 12) == 'codediff:///'
end

--- @async
--- @return string|nil
M.get_diffview_filename = function(buf_name)
  local view = require('diffview.lib').get_current_view()
  local file = view:infer_cur_file()
  if not file then
    return nil
  end

  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    ui.notify('No PR selected/checked out', vim.log.levels.WARN)
    return nil
  end

  local full_name = file.absolute_path

  config.log('get_diffview_filename. buf_name', buf_name)
  config.log('get_diffview_filename. full_name', full_name)
  config.log('get_diffview_filename. selected_pr.headRefOid', selected_pr.headRefOid)

  local commit_abbrev = selected_pr.headRefOid:sub(1, 11)

  local found = string.find(buf_name, commit_abbrev, 1, true)
  if found then
    return full_name
  end
end

--- @async
--- @return string|nil
M.get_codediff_filename = function(buf_name)
  -- Try using CodeDiff API first (Option C)
  local has_codediff, virtual_file = pcall(require, 'codediff.core.virtual_file')

  if has_codediff and virtual_file.parse_url then
    local git_root, commit, filepath = virtual_file.parse_url(buf_name)

    if not git_root or not commit or not filepath then
      config.log('get_codediff_filename: failed to parse URL', buf_name)
      return nil
    end

    -- Verify commit hash matches PR's headRefOid
    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected/checked out', vim.log.levels.WARN)
      return nil
    end

    config.log('get_codediff_filename. buf_name', buf_name)
    config.log('get_codediff_filename. git_root', git_root)
    config.log('get_codediff_filename. commit', commit)
    config.log('get_codediff_filename. filepath', filepath)
    config.log('get_codediff_filename. selected_pr.headRefOid', selected_pr.headRefOid)

    -- Check if commit matches PR (support both full and abbreviated hash)
    local commit_abbrev = selected_pr.headRefOid:sub(1, #commit)

    if commit == selected_pr.headRefOid or commit_abbrev == commit then
      -- Construct full absolute path
      return git_root .. '/' .. filepath
    end

    config.log('get_codediff_filename: commit mismatch', commit, selected_pr.headRefOid)
    return nil
  else
    -- Fallback: manual parsing (Option A)
    config.log('get_codediff_filename: CodeDiff API not available, using manual parsing')

    -- Pattern: codediff:///<git-root>///<commit>/<filepath>
    local pattern = '^codediff:///(.-)///([a-fA-F0-9]+)/(.+)$'
    local git_root, commit, filepath = buf_name:match(pattern)

    if not git_root or not commit or not filepath then
      config.log('get_codediff_filename: failed to parse buffer name', buf_name)
      return nil
    end

    local selected_pr = pr_utils.get_selected_pr()
    if selected_pr == nil then
      ui.notify('No PR selected/checked out', vim.log.levels.WARN)
      return nil
    end

    local commit_abbrev = selected_pr.headRefOid:sub(1, #commit)

    if commit == selected_pr.headRefOid or commit_abbrev == commit then
      return git_root .. '/' .. filepath
    end
    return nil
  end
end

M.load_comments_on_buffer_by_filename = function(bufnr, filename)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      config.log('load_comments_on_buffer_by_filename: buffer no longer valid', bufnr)
      return
    end

    config.log('load_comments_on_buffer filename', filename)
    if state.comments_list[filename] ~= nil then
      local diagnostics = {}
      for _, comment in pairs(state.comments_list[filename]) do
        if #comment.comments > 0 then
          config.log('comment to diagnostics', comment)
          table.insert(diagnostics, {
            lnum = comment.line - 1,
            col = 0,
            message = comment.content,
            severity = vim.diagnostic.severity.INFO,
            source = 'GHLite',
          })
        end
      end

      vim.diagnostic.set(vim.api.nvim_create_namespace('GHLiteNamespace'), bufnr, diagnostics, {})
    end
  end)
end

return M
