local gh = require "ghlite.gh"
local utils = require "ghlite.utils"
local config = require "ghlite.config"

local M = {}

M.selected_PR = nil

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
        M.selected_PR = tostring(pr.number)
        M.load_pr_view()
      end
    end)
end

function M.checkout()
  ui_selectPR('Select PR to checkout:',
    function(pr)
      if pr ~= nil then
        M.selected_PR = tostring(pr.number)
        gh.checkout_pr(M.selected_PR)
        M.load_pr_view()
      end
    end)
end

function M.get_selected_or_current_pr()
  if M.selected_PR ~= nil then
    return M.selected_PR
  end
  local current_pr = gh.get_current_pr()
  if current_pr ~= nil then
    return current_pr
  end
end

function M.load_pr_view()
  local pr_number = M.get_selected_or_current_pr()
  if pr_number == nil then
    vim.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  vim.notify('PR view loading started...')

  local pr_view = utils.system_str(string.format('gh pr view %s', pr_number))
  for i, line in ipairs(pr_view) do
    line = line:match("^%s*(.-)%s*$")
    pr_view[i] = line
  end

  table.insert(pr_view, '')
  table.insert(pr_view, 'Press Ctrl-A to approve PR')

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
  vim.notify('PR approve started...')
  gh.approve_pr(M.selected_PR)
  vim.notify('PR approved.')
end

return M
