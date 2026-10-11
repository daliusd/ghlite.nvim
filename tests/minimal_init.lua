vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. '/.tests/site/pack/deps/start/mini.nvim')
vim.opt.runtimepath:append(vim.fn.getcwd() .. '/.tests/site/pack/deps/start/async.nvim')

require('mini.test').setup({
  collect = {
    find_files = function()
      return vim.fn.globpath('tests', 'test_*.lua', true, true)
    end,
  },
})

-- Keep agent review sessions written by tests out of the real data directory.
require('ghlite.agent').dir = vim.fn.tempname() .. '/agent'
