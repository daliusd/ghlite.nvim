local gh = require "ghlite.gh"
local utils = require "ghlite.utils"
local config = require "ghlite.config"
local state = require "ghlite.state"
local comments_utils = require "ghlite.comments_utils"
local pr_utils = require "ghlite.pr_utils"

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
        })
      end
    end
  end

  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries, 'r')
    vim.cmd("cfirst")
  else
    vim.notify('No GH comments loaded.')
  end
end

M.load_comments = function()
  local checked_out_pr = pr_utils.get_checked_out_pr()
  if checked_out_pr == nil then
    vim.notify('No PR to work with.', vim.log.levels.WARN)
    return
  end

  vim.notify('Comment loading started...')
  state.comments_list = gh.load_comments(checked_out_pr.number)

  load_comments_to_quickfix_list()

  M.load_comments_on_current_buffer()
  vim.notify('Comments loaded.')
end

M.load_comments_only = function(pr_to_load)
  state.comments_list = gh.load_comments(pr_to_load)
end

M.load_comments_on_current_buffer = function()
  local current_buffer = vim.api.nvim_get_current_buf()
  M.load_comments_on_buffer(current_buffer)
end

M.load_comments_on_buffer = function(bufnr)
  if bufnr == state.diff_buffer_id then
    M.load_comments_on_diff_buffer(bufnr)
    return
  end

  if not pr_utils.is_pr_checked_out() then
    return
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

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
          source = "GHLite",
        })
      end
    end

    vim.diagnostic.set(vim.api.nvim_create_namespace("GHLiteNamespace"), bufnr, diagnostics, {})
  end
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
            source = "GHLite",
          })
        end
      end
    end
  end

  vim.diagnostic.set(vim.api.nvim_create_namespace("GHLiteDiffNamespace"), bufnr, diagnostics, {})
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

local function get_current_filename_and_line()
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
  else
    local is_pr_checked_out = pr_utils.is_pr_checked_out()
    local checked_out_pr = pr_utils.get_checked_out_pr()

    if not is_pr_checked_out then
      if checked_out_pr then
        vim.notify('Command canceled because of PR check out.', vim.log.levels.WARN)
      end
      return nil, nil
    end
  end

  return current_filename, current_start_line, current_line
end

M.comment_on_line = function()
  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    vim.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  local current_filename, current_start_line, current_line = get_current_filename_and_line()
  if current_filename == nil or current_start_line == nil or current_line == nil then
    vim.notify('You are on a branch without PR.', vim.log.levels.WARN)
    return
  end

  local git_root = utils.get_git_root()
  if current_filename:sub(1, #git_root) ~= git_root then
    vim.notify('File is not under git folder.', vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  if config.s.comment_split then
    vim.api.nvim_command(config.s.comment_split)
  end
  vim.api.nvim_set_current_buf(buf)
  local prompt = "<!-- Type your comment and press " .. config.s.keymaps.comment.send_comment .. ": -->"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt, "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local function capture_input_and_close()
    local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if input_lines[1] == prompt then
      table.remove(input_lines, 1)
    end
    local input = table.concat(input_lines, "\n")

    local conversations = {}
    if current_start_line == current_line then
      conversations = M.get_conversations(current_filename, current_line)
    end

    --- @param grouped_comment GroupedComment
    local function reply(grouped_comment)
      local resp = gh.reply_to_comment(state.selected_PR.number, input, grouped_comment.id)
      if resp['errors'] == nil then
        vim.notify('Reply sent.')
        local new_comment = comments_utils.convert_comment(resp)
        table.insert(grouped_comment.comments, new_comment)
        grouped_comment.content = comments_utils.prepare_content(grouped_comment.comments)
      else
        vim.notify('Failed to reply to comment.', vim.log.levels.WARN)
      end
    end

    vim.cmd('bwipeout')

    if #conversations == 1 then
      reply(conversations[1])
    elseif #conversations > 1 then
      vim.ui.select(
        conversations,
        {
          prompt = 'Select comment to reply to:',
          format_item = function(comment)
            return string.format('%s', vim.fn.split(comment.content, '\n')[1])
          end,
        },
        function(comment)
          if comment ~= nil then
            reply(comment)
          end
        end
      )
    else
      if current_filename:sub(1, #git_root) == git_root then
        local resp = gh.new_comment(state.selected_PR, input,
          current_filename:sub(#git_root + 2), current_start_line, current_line)
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

          vim.notify('Comment sent.')
        else
          vim.notify('Failed to send comment.', vim.log.levels.WARN)
        end
      end
    end

    M.load_comments_on_current_buffer()
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
  vim.api.nvim_buf_set_keymap(buf, 'i', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
end

M.open_comment = function()
  local current_filename, _, current_line = get_current_filename_and_line()
  if current_filename == nil then
    vim.notify('You are on a branch without PR.', vim.log.levels.WARN)
    return
  end

  local conversations = M.get_conversations(current_filename, current_line)

  if #conversations == 1 then
    utils.system({ config.s.open_command, conversations[1].url })
  elseif #conversations > 1 then
    vim.ui.select(
      conversations,
      {
        prompt = 'Select conversation to open in browser:',
        format_item = function(comment)
          return string.format('%s', vim.fn.split(comment.content, '\n')[1])
        end,
      },
      function(comment)
        if comment ~= nil then
          utils.system({ config.s.open_command, comment.url })
        end
      end
    )
  else
    vim.notify('No comments found on this line.', vim.log.levels.WARN)
  end
end

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
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  if config.s.comment_split then
    vim.api.nvim_command(config.s.comment_split)
  end
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.split(comment.body, '\n'))

  local function capture_input_and_close()
    local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(input_lines, "\n")

    vim.cmd('bwipeout')

    local resp = gh.update_comment(comment.id, input)
    if resp['errors'] == nil then
      vim.notify('Comment updated.')
      comment.body = resp.body
      conversation.content = comments_utils.prepare_content(conversation.comments)

      M.load_comments_on_current_buffer()
    else
      vim.notify('Failed to update the comment.', vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
  vim.api.nvim_buf_set_keymap(buf, 'i', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
end

M.update_comment = function()
  local current_filename, _, current_line = get_current_filename_and_line()
  if current_filename == nil then
    vim.notify('You are on a branch without PR.', vim.log.levels.WARN)
    return
  end

  local comments_list, conversations_list = get_own_comments(current_filename, current_line)

  if #comments_list == 0 then
    vim.notify('No comments found that could be updated.', vim.log.levels.WARN)
    return
  end

  vim.ui.select(
    comments_list,
    {
      prompt = 'Select comment to update:',
      format_item = function(comment)
        return string.format('%s: %s', comment.updated_at, vim.fn.split(comment.body, '\n')[1])
      end,
    },
    function(comment, idx)
      if comment ~= nil then
        edit_comment_body(comment, conversations_list[idx])
      end
    end
  )
end

M.delete_comment = function()
  local current_filename, _, current_line = get_current_filename_and_line()
  if current_filename == nil then
    vim.notify('You are on a branch without PR.', vim.log.levels.WARN)
    return
  end

  local comments_list, conversations_list = get_own_comments(current_filename, current_line)

  if #comments_list == 0 then
    vim.notify('No comments found that could be deleted.', vim.log.levels.WARN)
    return
  end

  vim.ui.select(
    comments_list,
    {
      prompt = 'Select comment to delete:',
      format_item = function(comment)
        return string.format('%s: %s', comment.updated_at, vim.fn.split(comment.body, '\n')[1])
      end,
    },
    function(comment, idx)
      if comment ~= nil then
        gh.delete_comment(comment.id)

        local function is_non_deleted_comment(c)
          return c.id ~= comment.id
        end

        local convo = conversations_list[idx]
        convo.comments = utils.filter_array(convo.comments, is_non_deleted_comment)
        convo.content = comments_utils.prepare_content(convo.comments)

        M.load_comments_on_current_buffer()
      end
    end
  )
end

return M
