local gh = require "ghlite.gh"
local config = require "ghlite.config"
local state = require "ghlite.state"
local utils = require "ghlite.utils"
local pr_utils = require "ghlite.pr_utils"

local M = {}

local function ui_selectPR(prompt, callback)
  utils.notify('Loading PR list...')
  gh.get_pr_list(function(prs)
    if #prs == 0 then
      utils.notify('No PRs found. Make sure you have `gh` configured.', vim.log.levels.WARN)
      return
    end

    vim.schedule(
      function()
        vim.ui.select(
          prs,
          {
            prompt = prompt,
            format_item = function(pr)
              local date = pr.createdAt:sub(1, 10)
              local draft = pr.isDraft and ' Draft' or ''
              local approved = pr.reviewDecision == 'APPROVED' and ' Approved' or ''

              local labels = ''
              for _, label in pairs(pr.labels) do
                labels = labels .. ', ' .. label.name
              end

              return string.format('#%s: %s (%s, %s%s%s%s)', pr.number, pr.title, pr.author.login, date, draft, approved,
                labels)
            end,
          },
          callback
        )
      end
    )
  end)
end

function M.select()
  ui_selectPR('Select PR:',
    function(pr)
      if pr ~= nil then
        state.selected_PR = pr
        M.load_pr_view()
      end
    end)
end

function M.checkout()
  ui_selectPR('Select PR to checkout:',
    function(pr)
      if pr ~= nil then
        state.selected_PR = pr
        gh.checkout_pr(state.selected_PR.number, M.load_pr_view)
      end
    end)
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
        reviews = reviews .. (idx > 1 and ', ' or '') .. string.format("%s (%s)", review.author.login, review.state)
      end
      table.insert(pr_view, reviews)
    end

    table.insert(pr_view, '')
    local body = string.gsub(pr_info.body, "\r", "")
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
        table.insert(pr_view, string.format("✍️ %s at %s:", comment.author.login, comment.createdAt))

        local comment_body = string.gsub(comment.body, "\r", "")

        -- NOTE: naive check if it is HTML comment
        if config.s.html_comments_command ~= false and comment.body:match("<%s*[%w%-]+.-%s*>") ~= nil then
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

    local buf = vim.api.nvim_create_buf(false, true)

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
      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.approve, '',
        { noremap = true, silent = true, callback = M.approve_pr })
    end
    if not utils.is_empty(config.s.keymaps.pr.request_changes) then
      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.request_changes, '',
        { noremap = true, silent = true, callback = M.request_changes_pr })
    end
    if not utils.is_empty(config.s.keymaps.pr.merge) then
      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.merge, '',
        { noremap = true, silent = true, callback = M.merge_pr })
    end
    if not utils.is_empty(config.s.keymaps.pr.comment) then
      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.comment, '',
        {
          noremap = true,
          silent = true,
          callback = function()
            M.comment_on_pr(M.load_pr_view)
          end
        })
    end
    if not utils.is_empty(config.s.keymaps.pr.diff) then
      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.diff, ':GHLitePRDiff<cr>',
        { noremap = true, silent = true })
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
      local buf = vim.api.nvim_create_buf(false, true)

      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].filetype = 'markdown'

      if config.s.comment_split then
        vim.api.nvim_command(config.s.comment_split)
      end
      vim.api.nvim_set_current_buf(buf)
      local prompt = "<!-- Type your PR comment and press " ..
          config.s.keymaps.comment.send_comment .. " to comment: -->"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt, "" })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local function capture_input_and_close()
        local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if input_lines[1] == prompt then
          table.remove(input_lines, 1)
        end
        local input = table.concat(input_lines, "\n")

        vim.cmd('bwipeout')

        utils.notify('Sending comment...')

        gh.new_pr_comment(state.selected_PR, input, function(resp)
          if resp ~= nil then
            utils.notify('Comment sent.')
            if type(on_success) == "function" then
              on_success()
            end
          else
            utils.notify('Failed to send comment.', vim.log.levels.WARN)
          end
        end)
      end

      vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.comment.send_comment, '',
        { noremap = true, silent = true, callback = capture_input_and_close })
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

    utils.notify('PR request changes started...')
    gh.request_changes_pr(selected_pr.number, function()
      utils.notify('PR request changes finished.')
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
