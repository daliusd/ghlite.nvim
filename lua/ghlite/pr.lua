local gh = require "ghlite.gh"
local utils = require "ghlite.utils"

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

return M
