local gh = require "ghlite.gh"
local utils = require "ghlite.utils"
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

  local pr_view = utils.system_str(string.format('gh pr view %s', selected_pr.number))
  for i, line in ipairs(pr_view) do
    line = line:match("^%s*(.-)%s*$")
    pr_view[i] = line
  end

  table.insert(pr_view, '')
  table.insert(pr_view, 'Press ' .. config.s.keymaps.pr.approve .. ' to approve PR')

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
