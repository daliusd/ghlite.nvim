local gh = require "ghlite.gh"
local utils = require "ghlite.utils"
local config = require "ghlite.config"

local M = {}

function M.checkout()
  local prs = gh.get_pr_list()

  if #prs == 0 then
    vim.print('No PRs found')
    return
  end

  vim.ui.select(
    prs,
    {
      prompt = 'Select PR to checkout:',
      format_item = function(pr)
        return string.format('#%s: %s (%s)', pr.number, pr.title, pr.author.login)
      end,
    },
    function(pr)
      if pr ~= nil then
        gh.checkout_pr(pr.number)
      end
    end
  )
end

function M.load_pr_view()
  vim.print('PR view loading started...')

  local pr_view = utils.readp('gh pr view')
  for i, line in ipairs(pr_view) do
    line = line:match("^%s*(.-)%s*$")
    pr_view[i] = line
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = 'nofile'

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pr_view)

  if config.view_split then
    vim.api.nvim_command(config.view_split)
  end
  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  vim.print('PR view loaded.')
end

return M