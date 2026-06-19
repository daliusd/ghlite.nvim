local T = MiniTest.new_set()
local expect = MiniTest.expect

local default_config

T['setup deep-merges user config without dropping defaults'] = function()
  package.loaded['ghlite.config'] = nil
  local config = require('ghlite.config')
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
  expect.equality(config.s.keymaps.comment.send_comment, default_config.keymaps.comment.send_comment)
  expect.equality(config.s.merge.approved, default_config.merge.approved)
end

return T
