local T = MiniTest.new_set()
local expect = MiniTest.expect

local default_config

T['setup deep-merges user config without dropping defaults'] = function()
  -- Load a fresh copy and put the shared one back afterwards: other modules keep a
  -- reference to it, so tests that run later would configure a stale table.
  local shared_config = package.loaded['ghlite.config']
  package.loaded['ghlite.config'] = nil
  local config = require('ghlite.config')
  package.loaded['ghlite.config'] = shared_config
  default_config = vim.deepcopy(config.s)

  config.setup({
    debug = true,
    keymaps = {
      diff = {
        open_file = '<CR>',
      },
    },
  })

  expect.equality(config.s.debug, true)
  expect.equality(config.s.keymaps.diff.open_file, '<CR>')
  expect.equality(config.s.keymaps.diff.approve, default_config.keymaps.diff.approve)
  expect.equality(config.s.keymaps.pr.diffview, 'cl')
  expect.equality(config.s.keymaps.comment.send_comment, default_config.keymaps.comment.send_comment)
  expect.equality(config.s.comment_hunk, default_config.comment_hunk)
  expect.equality(config.s.merge.approved, default_config.merge.approved)
end

return T
