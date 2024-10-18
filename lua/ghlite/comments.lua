local gh = require "ghlite.gh"
local utils = require "ghlite.utils"
local config = require "ghlite.config"

local M = {}

M.comments = {}

local function load_comments_to_quickfix_list()
  local qf_entries = {}

  local filenames = {}
  for fn in pairs(M.comments) do
    table.insert(filenames, fn)
  end
  table.sort(filenames)

  for _, filename in pairs(filenames) do
    local comments_in_file = M.comments[filename]

    table.sort(comments_in_file, function(a, b)
      return a.line < b.line
    end)

    for _, comment in pairs(comments_in_file) do
      table.insert(qf_entries, {
        filename = filename,
        lnum = comment.line,
      })
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
  vim.notify('Comment loading started...')
  M.comments = gh.load_comments()
  load_comments_to_quickfix_list()

  M.load_comments_on_current_buffer()
  vim.notify('Comments loaded.')
end

M.load_comments_on_current_buffer = function()
  local current_buffer = vim.api.nvim_get_current_buf()
  M.load_comments_on_buffer(current_buffer)
end

M.load_comments_on_buffer = function(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)

  config.log('load_comments_on_buffer filename', filename)
  if M.comments[filename] ~= nil then
    local diagnostics = {}
    for _, comment in pairs(M.comments[filename]) do
      config.log('comment to diagnostics', comment)
      table.insert(diagnostics, {
        lnum = comment.line - 1,
        col = 0,
        message = comment.content,
        severity = vim.diagnostic.severity.INFO,
        source = "GHLite",
      })
    end

    vim.diagnostic.set(vim.api.nvim_create_namespace("GHLiteNamespace"), bufnr, diagnostics, {})
  end
end

M.find_possible_conversations = function(current_filename, current_line)
  local possible_conversation = {}
  if M.comments[current_filename] ~= nil then
    for _, comment in pairs(M.comments[current_filename]) do
      if current_line == comment.line then
        table.insert(possible_conversation, comment)
      end
    end
  end
  return possible_conversation
end

M.comment_on_line = function()
  local pr = utils.readp('gh pr view --json number -q .number')[1]
  if pr == nil then
    vim.notify('You are on master.', vim.log.levels.WARN)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_filename = vim.api.nvim_buf_get_name(current_buf)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  if config.s.comment_split then
    vim.api.nvim_command(config.s.comment_split)
  end
  vim.api.nvim_set_current_buf(buf)
  local prompt = "<!-- Type your comment and press Ctrl + Enter: -->"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt, "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local function capture_input_and_close()
    local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if input_lines[1] == prompt then
      table.remove(input_lines, 1)
    end
    local input = table.concat(input_lines, "\n")

    local possible_conversation = M.find_possible_conversations(current_filename, current_line)

    local function reply(comment)
      local resp = gh.reply_to_comment(input, comment.id)
      if resp['errors'] == nil then
        vim.notify('Reply sent.')
        comment.content = comment.content .. gh.format_comment(gh.convert_comment(resp))
      else
        vim.notify('Failed to reply to comment.', vim.log.levels.WARN)
      end
    end

    vim.cmd('bwipeout')

    if #possible_conversation == 1 then
      reply(possible_conversation[1])
    elseif #possible_conversation > 1 then
      vim.ui.select(
        possible_conversation,
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
      local git_root = utils.get_git_root()
      if current_filename:sub(1, #git_root) == git_root then
        local resp = gh.new_comment(input, current_filename:sub(#git_root + 2), current_line)
        if resp['errors'] == nil then
          local new_comment_group = {
            id = resp.id,
            line = current_line,
            url = resp.html_url,
            content = gh.format_comment(gh.convert_comment(resp)),
          }
          if M.comments[current_filename] == nil then
            M.comments[current_filename] = { new_comment_group }
          else
            table.insert(M.comments[current_filename], new_comment_group)
          end

          vim.notify('Comment sent.')
        else
          vim.notify('Failed to send comment.', vim.log.levels.WARN)
        end
      end
    end
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
  vim.api.nvim_buf_set_keymap(buf, 'i', config.s.keymaps.comment.send_comment, '',
    { noremap = true, silent = true, callback = capture_input_and_close })
end

M.open_comment = function()
  local pr = utils.readp('gh pr view --json number -q .number')[1]
  if pr == nil then
    vim.notify('You are on master.', vim.log.levels.WARN)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_filename = vim.api.nvim_buf_get_name(current_buf)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  local possible_conversation = M.find_possible_conversations(current_filename, current_line)

  if #possible_conversation == 1 then
    utils.readpt({ config.s.open_command, possible_conversation[1].url })
  elseif #possible_conversation > 1 then
    vim.ui.select(
      possible_conversation,
      {
        prompt = 'Select conversation to open in browser:',
        format_item = function(comment)
          return string.format('%s', vim.fn.split(comment.content, '\n')[1])
        end,
      },
      function(comment)
        if comment ~= nil then
          utils.readpt({ config.s.open_command, comment.url })
        end
      end
    )
  else
    vim.notify('No comments found on this line.', vim.log.levels.WARN)
  end
end

return M
