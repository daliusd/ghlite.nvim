local T = MiniTest.new_set()
local expect = MiniTest.expect

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

local function with_agent_config(agent_config, fn)
  local config = require('ghlite.config')
  local original = config.s.agent
  config.s.agent = vim.tbl_extend('force', original, agent_config)
  local ok, err = pcall(fn)
  config.s.agent = original
  if not ok then
    error(err)
  end
end

local pr_info = {
  title = 'Add export',
  url = 'https://github.test/pr/7',
  reviews = { { author = { login = 'alice' }, state = 'COMMENTED', body = 'Looks close.' } },
  comments = { { author = { login = 'bob' }, body = 'Ping' } },
}

local function overrides(output_calls)
  local state = require('ghlite.state')
  return {
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return { number = 7, headRefOid = 'abcdef123456' }
      end,
    },
    ['ghlite.gh'] = {
      get_pr_info = function()
        return pr_info
      end,
    },
    ['ghlite.comments'] = {
      load_comments_only = function()
        state.comments_list = {
          ['/repo/lua/a.lua'] = {
            { line = 4, resolved = false, url = 'u1', comments = { { user = 'carol', body = 'Fix' } } },
          },
        }
      end,
    },
    ['ghlite.utils'] = {
      get_git_root = function()
        return '/repo'
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }
end

T['export_comments sends PR reviews, comments and threads to a custom output'] = function()
  local received
  with_agent_config({
    output = function(markdown, data)
      received = { markdown = markdown, data = data }
    end,
  }, function()
    with_overrides(overrides(), function()
      require('ghlite.export').export_comments():wait(1000)
    end)
  end)

  expect.equality(
    received.data.pr,
    { number = 7, title = 'Add export', url = 'https://github.test/pr/7', head = 'abcdef123456' }
  )
  expect.equality(#received.data.reviews, 1)
  expect.equality(#received.data.pr_comments, 1)
  expect.equality(received.data.threads[1].path, 'lua/a.lua')
  expect.equality(received.markdown:find('1. `lua/a.lua:4` @carol - Fix', 1, true) ~= nil, true)
  expect.equality(received.markdown:find('Head: abcdef1', 1, true) ~= nil, true)
end

T['export_comments honours github_comments and github_threads switches'] = function()
  local received
  with_agent_config({
    github_comments = false,
    github_threads = false,
    output = function(_, data)
      received = data
    end,
  }, function()
    with_overrides(overrides(), function()
      require('ghlite.export').export_comments():wait(1000)
    end)
  end)

  -- Nothing left to export, so the output is never called.
  expect.equality(received, nil)
end

T['export_comments copies to the clipboard registers by default'] = function()
  vim.fn.setreg('"', '')
  with_overrides(overrides(), function()
    require('ghlite.export').export_comments():wait(1000)
  end)

  expect.equality(vim.fn.getreg('"'):find('## Review threads', 1, true) ~= nil, true)
end

T['export_comments renders HTML comments without blocking the main loop'] = function()
  local config = require('ghlite.config')
  local original_command = config.s.html_comments_command
  config.s.html_comments_command = { 'sed', 's/<[^>]*>//g' }
  local original_comments = pr_info.comments
  pr_info.comments = { { author = { login = 'bot' }, body = '<p>Coverage <b>90%</b></p>' } }

  local received
  local ok, err = pcall(with_agent_config, {
    output = function(markdown)
      received = markdown
    end,
  }, function()
    with_overrides(
      vim.tbl_extend('force', overrides(), {
        ['ghlite.system'] = {
          run_sync = function()
            error('exports must not wait for HTML rendering on the main loop')
          end,
        },
      }),
      function()
        require('ghlite.export').export_comments():wait(5000)
      end
    )
  end)
  config.s.html_comments_command = original_command
  pr_info.comments = original_comments
  if not ok then
    error(err)
  end

  expect.equality(received:find('- @bot - Coverage 90%', 1, true) ~= nil, true)
end

return T
