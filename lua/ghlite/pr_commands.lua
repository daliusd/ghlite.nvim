local comments = require('ghlite.comments')
local config = require('ghlite.config')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local utils = require('ghlite.utils')

local M = {}

local function ui_selectPR(prompt, callback)
  utils.notify('Loading PR list...')
  gh.get_pr_list(function(prs)
    if #prs == 0 then
      utils.notify('No PRs found. Make sure you have `gh` configured.', vim.log.levels.WARN)
      return
    end

    vim.schedule(function()
      vim.ui.select(prs, {
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
      }, callback)
    end)
  end)
end

function M.select()
  ui_selectPR('Select PR:', function(pr)
    if pr ~= nil then
      state.selected_PR = pr
      M.load_pr_view()
    end
  end)
end

function M.checkout()
  ui_selectPR('Select PR to checkout:', function(pr)
    if pr ~= nil then
      state.selected_PR = pr
      gh.checkout_pr(state.selected_PR.number, M.load_pr_view)
    end
  end)
end

local function format_review_comments_for_pr_view()
  local review_section = {}

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
          local relative_filename = filename:match('^.*/(.*)$') or filename
          table.insert(review_section, string.format('### %s:%d', relative_filename, comment_group.line))
          table.insert(review_section, '')

          for _, comment in pairs(comment_group.comments) do
            local comment_body = string.gsub(comment.body, '\r', '')
            local comment_lines = vim.split(comment_body, '\n')

            if comment == comment_group.comments[1] then
              table.insert(review_section, string.format('> **%s** at %s:', comment.user, comment.updated_at))
            else
              table.insert(review_section, string.format('> **%s** replied at %s:', comment.user, comment.updated_at))
            end

            for _, line in ipairs(comment_lines) do
              table.insert(review_section, '> ' .. line)
            end
            table.insert(review_section, '')
          end
        end
      end
    end
  end

  return review_section
end

local function show_pr_info(pr_info)
  if pr_info == nil then
    utils.notify('PR view load failed', vim.log.levels.ERROR)
    return
  end

  vim.schedule(function()
    local pr_view = {
      string.format('#%d %s', pr_info.number, pr_info.title),
      string.format('Created by %s at %s', pr_info.author.login, pr_info.createdAt),
      string.format('URL: %s', pr_info.url),
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

    table.insert(pr_view, '')
    local body = string.gsub(pr_info.body, '\r', '')
    for _, line in ipairs(vim.split(body, '\n')) do
      table.insert(pr_view, line)
    end

    table.insert(pr_view, '')
    if not utils.is_empty(config.s.keymaps.pr.approve) then
      table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.approve .. ' to approve PR')
    end
    if not utils.is_empty(config.s.keymaps.pr.request_changes) then
      table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.request_changes .. ' to request PR changes')
    end
    if not utils.is_empty(config.s.keymaps.pr.merge) then
      table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.merge .. ' to merge PR')
    end
    if not utils.is_empty(config.s.keymaps.pr.comment) then
      table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.comment .. ' to comment on PR')
    end
    if not utils.is_empty(config.s.keymaps.pr.diff) then
      table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.diff .. ' to open PR diff')
    end

    if #pr_info.comments > 0 then
      table.insert(pr_view, '')
      table.insert(pr_view, 'Comments:')
      table.insert(pr_view, '')

      for _, comment in pairs(pr_info.comments) do
        table.insert(pr_view, string.format('✍️ %s at %s:', comment.author.login, comment.createdAt))

        local comment_body = string.gsub(comment.body, '\r', '')

        -- NOTE: naive check if it is HTML comment
        if config.s.html_comments_command ~= false and comment.body:match('<%s*[%w%-]+.-%s*>') ~= nil then
          local success, result = pcall(function()
            return vim.system(config.s.html_comments_command, { stdin = comment.body }):wait()
          end)
          if success then
            comment_body = result.stdout
          end
        end

        for _, line in ipairs(vim.split(comment_body, '\n')) do
          table.insert(pr_view, line)
        end
        table.insert(pr_view, '')
      end
    end

    -- Load review comments and add them to the PR view
    comments.load_comments_only(pr_info.number, function()
      vim.schedule(function()
        local review_section = format_review_comments_for_pr_view()
        if #review_section > 0 then
          local buf = vim.api.nvim_get_current_buf()
          local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

          -- Insert review comments before the keymap hints
          local insert_position = #current_lines
          for i = #current_lines, 1, -1 do
            if current_lines[i]:match('^Press .* to ') then
              insert_position = i - 1
            else
              break
            end
          end

          -- Add review comments section
          for i, line in ipairs(review_section) do
            table.insert(current_lines, insert_position + i, line)
          end

          -- Add an empty line before keymap hints
          table.insert(current_lines, insert_position + #review_section + 1, '')

          -- Temporarily make buffer modifiable to update it
          vim.bo[buf].readonly = false
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, current_lines)
          vim.bo[buf].readonly = true
          vim.bo[buf].modifiable = false
        end
      end)
    end)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'PR View: ' .. pr_info.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')')

    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = 'markdown'

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, pr_view)

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
          M.comment_on_pr(M.load_pr_view)
        end,
      })
    end
    if not utils.is_empty(config.s.keymaps.pr.diff) then
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        config.s.keymaps.pr.diff,
        ':GHLitePRDiff<cr>',
        { noremap = true, silent = true }
      )
    end

    utils.notify('PR view loaded.')
  end)
end

local function load_pr_view_for_pr(selected_pr)
  if selected_pr == nil then
    utils.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  utils.notify('PR view loading started...')

  gh.get_pr_info(selected_pr.number, show_pr_info)
end

function M.load_pr_view()
  pr_utils.get_selected_pr(load_pr_view_for_pr)
end

M.comment_on_pr = function(on_success)
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    vim.schedule(function()
      local prompt = '<!-- Type your PR comment and press '
        .. config.s.keymaps.comment.send_comment
        .. ' to comment: -->'

      utils.get_comment(
        'PR Comment: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
        config.s.comment_split,
        prompt,
        { prompt, '' },
        config.s.keymaps.comment.send_comment,
        function(input)
          utils.notify('Sending comment...')

          gh.new_pr_comment(state.selected_PR, input, function(resp)
            if resp ~= nil then
              utils.notify('Comment sent.')
              if type(on_success) == 'function' then
                on_success()
              end
            else
              utils.notify('Failed to send comment.', vim.log.levels.WARN)
            end
          end)
        end
      )
    end)
  end)
end

function M.approve_pr()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected to approve', vim.log.levels.ERROR)
    end

    utils.notify('PR approve started...')
    gh.approve_pr(selected_pr.number, function()
      utils.notify('PR approve finished.')
    end)
  end)
end

function M.request_changes_pr()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected to request changes', vim.log.levels.ERROR)
    end

    vim.schedule(function()
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
          utils.notify('PR request changes started...')
          gh.request_changes_pr(selected_pr.number, input, function()
            utils.notify('PR request changes finished.')
          end)
        end
      )
    end)
  end)
end

function M.merge_pr()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected to merge', vim.log.levels.ERROR)
      return
    end

    utils.notify('PR merge started...')
    if selected_pr.reviewDecision == 'APPROVED' then
      gh.merge_pr(selected_pr.number, config.s.merge.approved, function()
        utils.notify('PR merge finished.')
      end)
    else
      gh.merge_pr(selected_pr.number, config.s.merge.nonapproved, function()
        utils.notify('PR merge finished.')
      end)
    end
  end)
end

return M
