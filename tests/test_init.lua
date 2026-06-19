local T = MiniTest.new_set()
local expect = MiniTest.expect

T['setup registers all user commands'] = function()
  package.loaded['ghlite'] = nil
  require('ghlite').setup({})

  local expected_commands = {
    'GHLitePRSelect',
    'GHLitePRCheckout',
    'GHLitePRView',
    'GHLitePRApprove',
    'GHLitePRRequestChanges',
    'GHLitePRMerge',
    'GHLitePRAddPRComment',
    'GHLitePRLoadComments',
    'GHLitePRDiff',
    'GHLitePRDiffview',
    'GHLitePRAddComment',
    'GHLitePRUpdateComment',
    'GHLitePROpenComment',
    'GHLitePRDeleteComment',
  }

  for _, command in ipairs(expected_commands) do
    expect.equality(vim.fn.exists(':' .. command), 2)
  end
end

T['setup registers comment-loading autocmds'] = function()
  local autocmds = vim.api.nvim_get_autocmds({ pattern = '*' })
  local found = {}

  for _, autocmd in ipairs(autocmds) do
    if autocmd.event == 'BufReadPost' or autocmd.event == 'BufEnter' then
      found[autocmd.event] = autocmd.callback ~= nil
    end
  end

  expect.equality(found.BufReadPost, true)
  expect.equality(found.BufEnter, true)
end

T['GHLitePRAddComment is registered as a line-range command'] = function()
  local command = vim.api.nvim_get_commands({})['GHLitePRAddComment']

  expect.equality(command.range, '.')
end

return T
