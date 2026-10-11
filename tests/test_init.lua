local T = MiniTest.new_set()
local expect = MiniTest.expect

T['setup registers all user commands'] = function()
  package.loaded['ghlite'] = nil
  require('ghlite').setup({})

  local expected_commands = {
    'GHLitePRSelect',
    'GHLitePRList',
    'GHLitePRCheckout',
    'GHLitePRView',
    'GHLitePRApprove',
    'GHLitePRRequestChanges',
    'GHLitePRMerge',
    'GHLitePRAddPRComment',
    'GHLitePRLoadComments',
    'GHLitePRExportComments',
    'GHLitePRDiff',
    'GHLitePRDiffview',
    'GHLitePRAddComment',
    'GHLitePRUpdateComment',
    'GHLitePROpenComment',
    'GHLitePRDeleteComment',
    'GHLitePRResolveComment',
    'GHLitePRUnresolveComment',
    'GHLiteCommitView',
  }

  for _, command in ipairs(expected_commands) do
    expect.equality(vim.fn.exists(':' .. command), 2)
  end
end

T['setup registers comment-loading autocmds'] = function()
  local autocmds = vim.api.nvim_get_autocmds({ pattern = '*' })
  local found = {}

  for _, autocmd in ipairs(autocmds) do
    if
      vim.tbl_contains(
        { 'BufReadPost', 'BufEnter', 'BufWritePost', 'FileChangedShellPost', 'BufWipeout' },
        autocmd.event
      )
    then
      found[autocmd.event] = autocmd.callback ~= nil
    end
  end

  expect.equality(found.BufReadPost, true)
  expect.equality(found.BufEnter, true)
  expect.equality(found.BufWritePost, true)
  expect.equality(found.FileChangedShellPost, true)
  expect.equality(found.BufWipeout, true)
end

T['GHLitePRAddComment is registered as a line-range command'] = function()
  local command = vim.api.nvim_get_commands({})['GHLitePRAddComment']

  expect.equality(command.range, '.')
end

T['review commands complete the review kind that was typed'] = function()
  expect.equality(vim.fn.getcompletion('GHLitePRStartReview ag', 'cmdline'), { 'agent' })
  expect.equality(vim.fn.getcompletion('GHLitePRSubmitReview ', 'cmdline'), { 'github', 'agent' })
  expect.equality(vim.fn.getcompletion('GHLitePRDiscardReview gi', 'cmdline'), { 'github' })
end

return T
