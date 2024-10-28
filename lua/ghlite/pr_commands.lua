local gh = require "ghlite.gh"
local config = require "ghlite.config"
local state = require "ghlite.state"
local pr_utils = require "ghlite.pr_utils"

local M = {}

local function ui_selectPR(prompt, callback)
  local prs = gh.get_pr_list()

  if #prs == 0 then
    vim.notify('No PRs found', vim.log.levels.WARN)
    return
  end

  vim.ui.select(
    prs,
    {
      prompt = prompt,
      format_item = function(pr)
        local date = pr.createdAt:sub(1, 10)
        local draft = pr.isDraft and ' Draft' or ''
        local approved = pr.reviewDecision == 'APPROVED' and ' Approved' or ''
        return string.format('#%s: %s (%s, %s%s%s)', pr.number, pr.title, pr.author.login, date, draft, approved)
      end,
    },
    callback
  )
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
        gh.checkout_pr(state.selected_PR.number)
        M.load_pr_view()
      end
    end)
end

function M.load_pr_view()
  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    vim.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  vim.notify('PR view loading started...')

  local pr_info = gh.get_pr_info(selected_pr.number)
  vim.print(pr_info)
  if pr_info == nil then
    vim.notify('PR view load failed', vim.log.levels.ERROR)
    return
  end

  local pr_view = {
    string.format('#%d %s', pr_info.number, pr_info.title),
    string.format('Created by %s at %s', pr_info.author.login, pr_info.createdAt),
    string.format('URL: %s', pr_info.url),
    string.format('Changes files: %d', pr_info.changedFiles),
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
  table.insert(pr_view, pr_info.body)

  table.insert(pr_view, '')
  table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.approve .. ' to approve PR')

  if #pr_info.comments > 0 then
    table.insert(pr_view, '')
    table.insert(pr_view, 'Comments:')
    table.insert(pr_view, '')

    for _, comment in pairs(pr_info.comments) do
      table.insert(pr_view, string.format("%s at %s:", comment.author.login, comment.createdAt))
      table.insert(pr_view, comment.body)
      table.insert(pr_view, '')
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pr_view)

  if config.s.view_split then
    vim.api.nvim_command(config.s.view_split)
  end
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_set_keymap(buf, 'n', config.s.keymaps.pr.approve, '',
    { noremap = true, silent = true, callback = M.approve_pr })

  vim.notify('PR view loaded.')
end

function M.approve_pr()
  local selected_pr = pr_utils.get_selected_pr()
  if selected_pr == nil then
    vim.notify('No PR selected to approve', vim.log.levels.ERROR)
  end

  vim.notify('PR approve started...')
  gh.approve_pr(selected_pr.number)
  vim.notify('PR approved.')
end

return M
