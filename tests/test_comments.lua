local T = MiniTest.new_set()
local expect = MiniTest.expect

local function reset_state()
  local state = require('ghlite.state')
  state.selected_PR = nil
  state.comments_list = {}
  state.diff_buffer_id = nil
  state.filename_line_to_diff_line = {}
  state.diff_line_to_filename_line = {}
end

local function with_immediate_schedule(fn)
  local original_schedule = vim.schedule
  vim.schedule = function(cb)
    cb()
  end

  local ok, err = pcall(fn)
  vim.schedule = original_schedule

  if not ok then
    error(err)
  end
end

local function with_overrides(overrides, fn)
  local originals = {}
  for module_name, module_overrides in pairs(overrides) do
    local module = require(module_name)
    originals[module_name] = { module = module, values = {} }
    for key, value in pairs(module_overrides) do
      originals[module_name].values[key] = module[key]
      module[key] = value
    end
  end

  local ok, err = pcall(fn)

  for _, original in pairs(originals) do
    for key, value in pairs(original.values) do
      original.module[key] = value
    end
  end

  if not ok then
    error(err)
  end
end

T['get_conversations returns conversations on the requested file and line'] = function()
  reset_state()
  local state = require('ghlite.state')
  state.comments_list = {
    ['/repo/a.lua'] = {
      { line = 3, id = 1 },
      { line = 4, id = 2 },
      { line = 3, id = 3 },
    },
  }

  local comments = require('ghlite.comments')
  local result = comments.get_conversations('/repo/a.lua', 3)

  expect.equality(result, { { line = 3, id = 1 }, { line = 3, id = 3 } })
  expect.equality(comments.get_conversations('/repo/missing.lua', 3), {})
end

T['load_comments_on_buffer_by_filename sets diagnostics for non-empty conversations'] = function()
  with_immediate_schedule(function()
    reset_state()
    local state = require('ghlite.state')
    local comments = require('ghlite.comments')
    local bufnr = vim.api.nvim_create_buf(false, true)

    state.comments_list = {
      ['/repo/a.lua'] = {
        { line = 7, content = 'First comment', comments = { { id = 1 } } },
        { line = 9, content = 'Empty conversation', comments = {} },
      },
    }

    comments.load_comments_on_buffer_by_filename(bufnr, '/repo/a.lua')

    local diagnostics = vim.diagnostic.get(bufnr)
    expect.equality(#diagnostics, 1)
    expect.equality(diagnostics[1].lnum, 6)
    expect.equality(diagnostics[1].message, 'First comment')
    expect.equality(diagnostics[1].source, 'GHLite')

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end

T['load_comments_on_diff_buffer maps file comment lines to diff diagnostics'] = function()
  with_immediate_schedule(function()
    reset_state()
    local state = require('ghlite.state')
    local comments = require('ghlite.comments')
    local bufnr = vim.api.nvim_create_buf(false, true)

    state.comments_list = {
      ['/repo/a.lua'] = {
        { line = 20, content = 'Mapped comment', comments = { { id = 1 } } },
        { line = 21, content = 'Unmapped comment', comments = { { id = 2 } } },
      },
      ['/repo/missing.lua'] = {
        { line = 1, content = 'Missing file', comments = { { id = 3 } } },
      },
    }
    state.filename_line_to_diff_line = {
      ['/repo/a.lua'] = {
        [20] = 5,
      },
    }

    comments.load_comments_on_diff_buffer(bufnr)

    local diagnostics = vim.diagnostic.get(bufnr)
    expect.equality(#diagnostics, 1)
    expect.equality(diagnostics[1].lnum, 4)
    expect.equality(diagnostics[1].message, 'Mapped comment')
    expect.equality(diagnostics[1].source, 'GHLite')

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end

T['open_comment opens the only conversation on the current line'] = function()
  with_immediate_schedule(function()
    reset_state()
    local state = require('ghlite.state')
    local comments = require('ghlite.comments')
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, '/repo/a.lua')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    state.comments_list = {
      ['/repo/a.lua'] = {
        { line = 4, url = 'https://github.test/comment/1', content = 'Comment', comments = { { id = 1 } } },
      },
    }

    local system_call
    with_overrides({
      ['ghlite.pr_utils'] = {
        is_pr_checked_out = function(cb)
          cb(true)
        end,
        get_checked_out_pr = function(cb)
          cb({ number = 1 })
        end,
      },
      ['ghlite.utils'] = {
        system_cb = function(cmd)
          system_call = cmd
        end,
      },
    }, function()
      comments.open_comment()
    end)

    expect.equality(system_call, { 'open', 'https://github.test/comment/1' })
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end

T['get_codediff_filename parses fallback URLs and validates PR commit'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  package.loaded['codediff.core.virtual_file'] = nil

  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function(cb)
        cb({ headRefOid = 'abcdef1234567890' })
      end,
    },
  }, function()
    local result
    comments.get_codediff_filename('codediff:////repo///abcdef12345/lua/a.lua', function(filename)
      result = filename
    end)

    expect.equality(result, '/repo/lua/a.lua')
  end)
end

T['buffer type helpers identify diffview and codediff buffers'] = function()
  local comments = require('ghlite.comments')

  expect.equality(comments.is_in_diffview('diffview://tab/file.lua'), true)
  expect.equality(comments.is_in_diffview('/repo/file.lua'), false)
  expect.equality(comments.is_in_codediff('codediff:///repo///abc/file.lua'), true)
  expect.equality(comments.is_in_codediff('/repo/file.lua'), false)
end

return T
