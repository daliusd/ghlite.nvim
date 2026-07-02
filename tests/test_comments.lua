local async = require('async')

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
      is_pr_checked_out = function()
        return true
      end,
      get_checked_out_pr = function()
        return { number = 1 }
      end,
    },
    ['ghlite.system'] = {
      run = function(cmd)
        system_call = cmd
      end,
    },
  }, function()
    comments.open_comment():wait(1000)
  end)

  expect.equality(system_call, { 'open', 'https://github.test/comment/1' })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['get_codediff_filename parses fallback URLs and validates PR commit'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  package.loaded['codediff.core.virtual_file'] = nil

  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return { headRefOid = 'abcdef1234567890' }
      end,
    },
  }, function()
    local result = async
      .run(function()
        return comments.get_codediff_filename('codediff:////repo///abcdef12345/lua/a.lua')
      end)
      :wait(1000)

    expect.equality(result, '/repo/lua/a.lua')
  end)
end

T['comment_on_line creates a new comment and stores it locally'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  state.selected_PR = { number = 12, headRefOid = 'abc123' }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, '/repo/lua/a.lua')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local new_comment_call
  local refresh_count = 0
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
      is_pr_checked_out = function()
        return true
      end,
      get_checked_out_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.utils'] = {
      get_git_root = function()
        return '/repo'
      end,
      get_comment = function(_, _, _, _, _, cb)
        cb('new body')
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
    ['ghlite.gh'] = {
      new_comment = function(selected_pr, body, path, start_line, line)
        new_comment_call = {
          selected_pr = selected_pr,
          body = body,
          path = path,
          start_line = start_line,
          line = line,
        }
        return {
          id = 101,
          html_url = 'https://github.test/comment/101',
          path = 'lua/a.lua',
          line = line,
          start_line = start_line,
          user = { login = 'alice' },
          body = body,
          updated_at = 'now',
          diff_hunk = '@@ -2 +2 @@',
        }
      end,
    },
    ['ghlite.comments'] = {
      load_comments_on_current_buffer = function()
        refresh_count = refresh_count + 1
      end,
    },
  }, function()
    comments.comment_on_line():wait(1000)
  end)

  expect.equality(new_comment_call, {
    selected_pr = state.selected_PR,
    body = 'new body',
    path = 'lua/a.lua',
    start_line = 2,
    line = 2,
  })
  expect.equality(#state.comments_list['/repo/lua/a.lua'], 1)
  expect.equality(state.comments_list['/repo/lua/a.lua'][1].id, 101)
  expect.equality(state.comments_list['/repo/lua/a.lua'][1].comments[1].body, 'new body')
  expect.equality(refresh_count, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['comment_on_line replies to the existing conversation and updates content'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  state.selected_PR = { number = 12, headRefOid = 'abc123' }
  state.comments_list = {
    ['/repo/lua/a.lua'] = {
      {
        id = 55,
        line = 2,
        start_line = 2,
        url = 'https://github.test/comment/55',
        content = 'old content',
        comments = {
          {
            id = 55,
            url = 'https://github.test/comment/55',
            path = 'lua/a.lua',
            line = 2,
            start_line = 2,
            user = 'alice',
            body = 'Root',
            updated_at = 'before',
            diff_hunk = '@@ -2 +2 @@',
          },
        },
      },
    },
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, '/repo/lua/a.lua')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local reply_call
  local refresh_count = 0
  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
      is_pr_checked_out = function()
        return true
      end,
      get_checked_out_pr = function()
        return state.selected_PR
      end,
    },
    ['ghlite.utils'] = {
      get_git_root = function()
        return '/repo'
      end,
      get_comment = function(_, _, _, _, _, cb)
        cb('reply body')
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
    ['ghlite.gh'] = {
      reply_to_comment = function(pr_number, body, reply_to)
        reply_call = { pr_number = pr_number, body = body, reply_to = reply_to }
        return {
          id = 56,
          html_url = 'https://github.test/comment/56',
          path = 'lua/a.lua',
          line = 2,
          start_line = 2,
          user = { login = 'bob' },
          body = body,
          updated_at = 'after',
          diff_hunk = '@@ -2 +2 @@',
        }
      end,
    },
    ['ghlite.comments'] = {
      load_comments_on_current_buffer = function()
        refresh_count = refresh_count + 1
      end,
    },
  }, function()
    comments.comment_on_line():wait(1000)
  end)

  local conversation = state.comments_list['/repo/lua/a.lua'][1]
  expect.equality(reply_call, { pr_number = 12, body = 'reply body', reply_to = 55 })
  expect.equality(#conversation.comments, 2)
  expect.equality(conversation.comments[2].body, 'reply body')
  expect.equality(conversation.content:find('reply body', 1, true) ~= nil, true)
  expect.equality(refresh_count, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['update_comment updates the selected own comment and refreshes content'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  state.comments_list = {
    ['/repo/lua/a.lua'] = {
      {
        id = 55,
        line = 2,
        start_line = 2,
        url = 'https://github.test/comment/55',
        content = 'old content',
        comments = {
          {
            id = 55,
            url = 'https://github.test/comment/55',
            path = 'lua/a.lua',
            line = 2,
            start_line = 2,
            user = 'alice',
            body = 'Old body',
            updated_at = 'before',
            diff_hunk = '@@ -2 +2 @@',
          },
        },
      },
    },
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, '/repo/lua/a.lua')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local update_call
  local refresh_count = 0
  with_overrides({
    ['ghlite.pr_utils'] = {
      is_pr_checked_out = function()
        return true
      end,
      get_checked_out_pr = function()
        return { number = 12 }
      end,
    },
    ['ghlite.utils'] = {
      get_comment = function(_, _, _, _, _, cb)
        cb('Updated body')
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
      select = function(items, _)
        return items[1], 1
      end,
    },
    ['ghlite.gh'] = {
      get_user = function()
        return 'alice'
      end,
      update_comment = function(comment_id, body)
        update_call = { comment_id = comment_id, body = body }
        return { id = comment_id, body = body }
      end,
    },
    ['ghlite.comments'] = {
      load_comments_on_current_buffer = function()
        refresh_count = refresh_count + 1
      end,
    },
  }, function()
    comments.update_comment():wait(1000)
  end)

  local conversation = state.comments_list['/repo/lua/a.lua'][1]
  expect.equality(update_call, { comment_id = 55, body = 'Updated body' })
  expect.equality(conversation.comments[1].body, 'Updated body')
  expect.equality(conversation.content:find('Updated body', 1, true) ~= nil, true)
  expect.equality(refresh_count, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['delete_comment deletes the selected own comment and refreshes content'] = function()
  reset_state()
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  state.comments_list = {
    ['/repo/lua/a.lua'] = {
      {
        id = 55,
        line = 2,
        start_line = 2,
        url = 'https://github.test/comment/55',
        content = 'old content',
        comments = {
          {
            id = 55,
            url = 'https://github.test/comment/55',
            path = 'lua/a.lua',
            line = 2,
            start_line = 2,
            user = 'alice',
            body = 'Delete me',
            updated_at = 'before',
            diff_hunk = '@@ -2 +2 @@',
          },
          {
            id = 56,
            url = 'https://github.test/comment/56',
            path = 'lua/a.lua',
            line = 2,
            start_line = 2,
            user = 'bob',
            body = 'Keep me',
            updated_at = 'after',
            diff_hunk = '@@ -2 +2 @@',
          },
        },
      },
    },
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, '/repo/lua/a.lua')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local deleted_comment_id
  local refresh_count = 0
  with_overrides({
    ['ghlite.pr_utils'] = {
      is_pr_checked_out = function()
        return true
      end,
      get_checked_out_pr = function()
        return { number = 12 }
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
      select = function(items, _)
        return items[1], 1
      end,
    },
    ['ghlite.gh'] = {
      get_user = function()
        return 'alice'
      end,
      delete_comment = function(comment_id)
        deleted_comment_id = comment_id
        return ''
      end,
    },
    ['ghlite.comments'] = {
      load_comments_on_current_buffer = function()
        refresh_count = refresh_count + 1
      end,
    },
  }, function()
    comments.delete_comment():wait(1000)
  end)

  local conversation = state.comments_list['/repo/lua/a.lua'][1]
  expect.equality(deleted_comment_id, 55)
  expect.equality(#conversation.comments, 1)
  expect.equality(conversation.comments[1].id, 56)
  expect.equality(conversation.content:find('Keep me', 1, true) ~= nil, true)
  expect.equality(refresh_count, 1)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['buffer type helpers identify diffview and codediff buffers'] = function()
  local comments = require('ghlite.comments')

  expect.equality(comments.is_in_diffview('diffview://tab/file.lua'), true)
  expect.equality(comments.is_in_diffview('/repo/file.lua'), false)
  expect.equality(comments.is_in_codediff('codediff:///repo///abc/file.lua'), true)
  expect.equality(comments.is_in_codediff('/repo/file.lua'), false)
end

return T
