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

local root = '/repo'

local function reset()
  local agent = require('ghlite.agent')
  local state = require('ghlite.state')
  agent.reset_cache()
  os.remove(agent.session_file(root))
  state.review_target = nil
  state.selected_PR = nil
  state.pending_reviews = {}
  state.pending_reviews_checked = {}
  state.diff_buffer_id = nil
  state.diff_is_local = false
  state.filename_line_to_diff_line = {}
  state.diff_line_to_filename_line = {}
end

local function agent_overrides(extra)
  return vim.tbl_deep_extend('force', {
    ['ghlite.agent'] = {
      root = function()
        return root
      end,
    },
    ['ghlite.ui'] = {
      notify = function() end,
    },
  }, extra or {})
end

--- @param name string
--- @param line integer
--- @return integer bufnr
local function open_buffer(name, line)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'one', 'two', 'three', 'four' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  return bufnr
end

T['sessions persist drafts on disk and survive a cache reset'] = function()
  reset()
  local agent = require('ghlite.agent')

  local _, created = agent.start(root)
  expect.equality(created, true)
  agent.add_draft(root, 'lua/a.lua', 2, 3, 'Handle nil')
  local draft = agent.add_draft(root, 'lua/a.lua', 3, 3, 'Rename')
  expect.equality(agent.update_draft(root, draft.id, 'Rename it'), true)
  expect.equality(agent.update_draft(root, 99, 'Missing'), false)

  agent.reset_cache()
  local restored = agent.get(root)
  expect.equality(#restored.drafts, 2)
  expect.equality(restored.root, root)
  expect.equality(restored.next_id, 3)
  expect.equality(
    vim.tbl_map(function(d)
      return d.body
    end, restored.drafts),
    { 'Handle nil', 'Rename it' }
  )

  local _, created_again = agent.start(root)
  expect.equality(created_again, false)

  agent.delete_draft(root, restored.drafts[1].id)
  agent.reset_cache()
  expect.equality(#agent.get(root).drafts, 1)

  agent.discard(root)
  agent.reset_cache()
  expect.equality(agent.get(root), nil)
end

--- Write the session file the way another Neovim instance would.
--- @param drafts AgentDraft[]
--- @param next_id number
local function write_from_other_instance(drafts, next_id)
  local agent = require('ghlite.agent')
  local path = agent.session_file(root)
  vim.fn.writefile({ vim.json.encode({ next_id = next_id, drafts = drafts }) }, path)
  -- Make sure the modification time differs even on coarse-grained file systems.
  local stat = vim.uv.fs_stat(path)
  vim.uv.fs_utime(path, stat.atime.sec, stat.mtime.sec + 5)
end

T['drafts written by another Neovim are kept when this one changes the session'] = function()
  reset()
  local agent = require('ghlite.agent')
  agent.start(root)
  local mine = agent.add_draft(root, 'lua/a.lua', 1, 1, 'Mine')

  write_from_other_instance({
    mine,
    { id = 2, path = 'lua/b.lua', start_line = 4, line = 4, body = 'Theirs', created_at = 'now' },
  }, 3)
  expect.equality(#agent.get(root).drafts, 2)

  local next_draft = agent.add_draft(root, 'lua/a.lua', 7, 7, 'Mine again')
  expect.equality(next_draft.id, 3)
  agent.reset_cache()
  expect.equality(
    vim.tbl_map(function(draft)
      return draft.body
    end, agent.get(root).drafts),
    { 'Mine', 'Theirs', 'Mine again' }
  )
end

T['a change written within the same timestamp tick is not lost'] = function()
  reset()
  local agent = require('ghlite.agent')
  agent.start(root)
  local mine = agent.add_draft(root, 'lua/a.lua', 1, 1, 'Mine')
  local path = agent.session_file(root)
  -- Pin the timestamp to a whole second, so it can be reproduced exactly below.
  local tick = os.time() - 60
  vim.uv.fs_utime(path, tick, tick)
  expect.equality(#agent.get(root).drafts, 1)

  -- Another Neovim writes, and the file system gives it the same modification time.
  vim.fn.writefile({
    vim.json.encode({
      next_id = 3,
      drafts = { mine, { id = 2, path = 'lua/b.lua', start_line = 4, line = 4, body = 'Theirs', created_at = 'now' } },
    }),
  }, path)
  vim.uv.fs_utime(path, tick, tick)

  agent.add_draft(root, 'lua/a.lua', 7, 7, 'Mine again')
  agent.reset_cache()
  expect.equality(
    vim.tbl_map(function(draft)
      return draft.body
    end, agent.get(root).drafts),
    { 'Mine', 'Theirs', 'Mine again' }
  )
  expect.equality(vim.uv.fs_stat(path .. '.lock'), nil)
end

T['a lock left behind by a crashed Neovim is taken over'] = function()
  reset()
  local agent = require('ghlite.agent')
  agent.start(root)
  local lock_path = agent.session_file(root) .. '.lock'
  vim.fn.writefile({}, lock_path)
  local old = os.time() - agent.stale_lock_seconds - 10
  vim.uv.fs_utime(lock_path, old, old)

  local started = vim.uv.hrtime()
  expect.equality(agent.add_draft(root, 'lua/a.lua', 1, 1, 'After crash') ~= nil, true)
  expect.equality((vim.uv.hrtime() - started) / 1e6 < 500, true)
  expect.equality(vim.uv.fs_stat(lock_path), nil)
end

T['a session ended by another Neovim is noticed and its drafts are not resurrected'] = function()
  reset()
  local agent = require('ghlite.agent')
  agent.start(root)
  os.remove(agent.session_file(root))

  expect.equality(agent.get(root), nil)
  expect.equality(agent.add_draft(root, 'lua/a.lua', 1, 1, 'Late'), nil)
  expect.equality(vim.uv.fs_stat(agent.session_file(root)), nil)
end

T['writes leave no temporary files and an unreadable session is backed up'] = function()
  reset()
  local agent = require('ghlite.agent')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 1, 1, 'Body')
  local path = agent.session_file(root)
  expect.equality(vim.fn.glob(path .. '.*.tmp'), '')

  vim.fn.writefile({ '{"next_id": 2, "drafts": [' }, path)
  agent.reset_cache()
  expect.equality(agent.get(root), nil)
  local _, created = agent.start(root)
  expect.equality(created, true)
  expect.equality(vim.fn.readfile(path .. '.bak'), { '{"next_id": 2, "drafts": [' })
  os.remove(path .. '.bak')
end

--- @param agent table ghlite.agent
--- @return boolean
local function is_target(agent)
  return require('async')
    .run(function()
      return agent.is_target(root)
    end)
    :wait(1000)
end

T['is_target follows the review started last while its PR has a pending review'] = function()
  reset()
  local agent = require('ghlite.agent')
  local state = require('ghlite.state')
  state.selected_PR = { number = 12 }
  state.pending_reviews = { [12] = { id = 3, node_id = 'PRR_three', pr_number = 12 } }
  state.pending_reviews_checked = { [12] = true, [13] = true }

  with_overrides({
    ['ghlite.pr_utils'] = {
      get_selected_pr = function()
        return state.selected_PR
      end,
    },
  }, function()
    expect.equality(is_target(agent), false)
    agent.start(root)
    expect.equality(is_target(agent), true)
    state.review_target = 'github'
    expect.equality(is_target(agent), false)
    -- A PR without a pending review would post comments immediately, so they stay local.
    state.selected_PR = { number = 13 }
    expect.equality(is_target(agent), true)
    state.selected_PR = { number = 12 }
    -- A restart forgets the target; the restored agent session takes comments again.
    state.review_target = nil
    agent.reset_cache()
    expect.equality(is_target(agent), true)
    agent.discard(root)
    expect.equality(is_target(agent), false)
  end)
end

T['comment_on_line stores an agent draft without a PR and never calls GitHub'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  agent.start(root)
  local bufnr = open_buffer('/repo/lua/a.lua', 3)

  local prompt_content
  with_overrides(
    agent_overrides({
      ['ghlite.pr_utils'] = {
        get_selected_pr = function()
          error('agent comments must not need a PR')
        end,
      },
      ['ghlite.gh'] = {
        new_comment = function()
          error('agent comments must not reach GitHub')
        end,
      },
      ['ghlite.utils'] = {
        get_comment = function(_, _, _, content, _, cb)
          prompt_content = content
          cb('Handle the empty case')
        end,
      },
    }),
    function()
      comments.comment_on_line():wait(1000)
    end
  )

  expect.equality(prompt_content[1]:find('[agent]', 1, true) ~= nil, true)
  local session = agent.get(root)
  expect.equality(#session.drafts, 1)
  expect.equality(session.drafts[1].path, 'lua/a.lua')
  expect.equality(session.drafts[1].line, 3)
  expect.equality(session.drafts[1].body, 'Handle the empty case')

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

--- Run comment_on_line with a GitHub review started after the agent review.
--- @param pending_review PendingReview|nil pending review GitHub holds for the PR
--- @return string prompt first line of the comment prompt
local function comment_with_github_target(pending_review)
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  agent.start(root)
  state.review_target = 'github'
  state.selected_PR = { number = 12, headRefName = 'feature' }
  state.pending_reviews = { [12] = pending_review }
  state.pending_reviews_checked = { [12] = true }
  local bufnr = open_buffer('/repo/lua/a.lua', 2)

  local prompt
  with_overrides(
    agent_overrides({
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
          return root
        end,
        get_comment = function(_, _, _, content)
          prompt = content[1]
        end,
      },
    }),
    function()
      comments.comment_on_line():wait(1000)
    end
  )
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return prompt
end

T['comment_on_line joins the GitHub review started after the agent one'] = function()
  reset()
  local prompt = comment_with_github_target({ id = 3, node_id = 'PRR_three', pr_number = 12 })

  expect.equality(prompt:find('[agent]', 1, true), nil)
end

T['comment_on_line keeps comments local when the GitHub review is no longer pending'] = function()
  reset()
  -- E.g. the PR was switched, or its review was submitted in the web UI.
  local prompt = comment_with_github_target(nil)

  expect.equality(prompt:find('[agent]', 1, true) ~= nil, true)
end

T['update_comment and delete_comment edit agent drafts on the cursor line'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Old body')
  agent.add_draft(root, 'lua/a.lua', 4, 4, 'Other line')
  local bufnr = open_buffer('/repo/lua/a.lua', 2)

  local overrides = agent_overrides({
    ['ghlite.gh'] = {
      get_user = function()
        error('agent drafts must not reach GitHub')
      end,
    },
    ['ghlite.utils'] = {
      get_comment = function(_, _, _, _, _, cb)
        cb('New body')
      end,
    },
  })
  with_overrides(overrides, function()
    comments.update_comment():wait(1000)
  end)
  expect.equality(agent.get(root).drafts[1].body, 'New body')

  with_overrides(overrides, function()
    comments.delete_comment():wait(1000)
  end)
  expect.equality(
    vim.tbl_map(function(d)
      return d.body
    end, agent.get(root).drafts),
    { 'Other line' }
  )

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['agent drafts show as diagnostics in file buffers'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 3, 3, 'Draft body')
  local bufnr = open_buffer('/repo/lua/a.lua', 1)

  local original_schedule = vim.schedule
  vim.schedule = function(cb)
    cb()
  end
  local ok, err = pcall(with_overrides, agent_overrides(), function()
    comments.load_comments_on_buffer(bufnr)
  end)
  vim.schedule = original_schedule
  if not ok then
    error(err)
  end

  local diagnostics = vim.diagnostic.get(bufnr, { namespace = vim.api.nvim_create_namespace('GHLiteAgentNamespace') })
  expect.equality(#diagnostics, 1)
  expect.equality(diagnostics[1].lnum, 2)
  expect.equality(diagnostics[1].source, 'GHLite agent')
  expect.equality(diagnostics[1].message:find('Draft body', 1, true) ~= nil, true)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['start_review agent starts a session without a PR and rejects unknown kinds'] = function()
  reset()
  local agent = require('ghlite.agent')
  local pr_commands = require('ghlite.pr_commands')
  local state = require('ghlite.state')

  local errors = {}
  with_overrides(
    agent_overrides({
      ['ghlite.ui'] = {
        notify = function(message, level)
          if level == vim.log.levels.ERROR then
            table.insert(errors, message)
          end
        end,
      },
    }),
    function()
      pr_commands.start_review('gitlab'):wait(1000)
      pr_commands.start_review('agent'):wait(1000)
    end
  )

  expect.equality(#errors, 1)
  expect.equality(agent.get(root) ~= nil, true)
  expect.equality(state.review_target, 'agent')
end

T['start_review without an argument uses default_review'] = function()
  reset()
  local agent = require('ghlite.agent')
  local config = require('ghlite.config')
  local pr_commands = require('ghlite.pr_commands')

  config.s.default_review = 'agent'
  local ok, err = pcall(with_overrides, agent_overrides(), function()
    pr_commands.start_review():wait(1000)
  end)
  config.s.default_review = 'github'
  if not ok then
    error(err)
  end

  expect.equality(agent.get(root) ~= nil, true)
end

T['submit_review exports the agent drafts with the summary and ends the session'] = function()
  reset()
  local agent = require('ghlite.agent')
  local config = require('ghlite.config')
  local pr_commands = require('ghlite.pr_commands')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Handle nil')

  local exported
  local original_output = config.s.agent.output
  config.s.agent.output = function(markdown)
    exported = markdown
  end
  local ok, err = pcall(
    with_overrides,
    agent_overrides({
      ['ghlite.pr_utils'] = {
        get_selected_pr = function()
          return nil
        end,
      },
      ['ghlite.utils'] = {
        get_comment = function(_, _, _, _, _, cb)
          cb('Overall fine')
        end,
      },
    }),
    function()
      pr_commands.submit_review():wait(1000)
      -- The export runs in a task started from the summary callback.
      vim.wait(1000, function()
        return agent.get(root) == nil
      end)
    end
  )
  config.s.agent.output = original_output
  if not ok then
    error(err)
  end

  expect.equality(exported:find('Summary: Overall fine', 1, true) ~= nil, true)
  expect.equality(exported:find('1. `lua/a.lua:2` - Handle nil', 1, true) ~= nil, true)
  expect.equality(agent.get(root), nil)
end

T['discard_review agent asks before dropping drafts'] = function()
  reset()
  local agent = require('ghlite.agent')
  local pr_commands = require('ghlite.pr_commands')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Handle nil')

  local function discard(choice)
    local question
    with_overrides(
      agent_overrides({
        ['ghlite.ui'] = {
          confirm = function(message)
            question = message
            return choice
          end,
        },
      }),
      function()
        pr_commands.discard_review():wait(1000)
      end
    )
    return question
  end

  expect.equality(discard(2), 'Discard the agent review and its 1 comment?')
  expect.equality(#agent.get(root).drafts, 1)

  discard(1)
  agent.reset_cache()
  expect.equality(agent.get(root), nil)
  expect.equality(is_target(agent), false)
end

T['discard_review agent ends an empty review without asking'] = function()
  reset()
  local agent = require('ghlite.agent')
  local pr_commands = require('ghlite.pr_commands')
  agent.start(root)

  with_overrides(
    agent_overrides({
      ['ghlite.ui'] = {
        confirm = function()
          error('an empty review has nothing to lose')
        end,
      },
    }),
    function()
      pr_commands.discard_review('agent'):wait(1000)
    end
  )

  expect.equality(agent.get(root), nil)
end

--- Run `fn` inside a throwaway git repository: `main` with one commit, checked out on
--- `feature` with one more commit and an uncommitted change.
local function in_temp_repo(fn)
  local dir = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  local function git(...)
    local result = vim
      .system(vim.list_extend({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t', '-C', dir }, { ... }), { text = true })
      :wait()
    assert(result.code == 0, result.stderr)
  end
  git('init', '-q', '-b', 'main')
  vim.fn.writefile({ 'one', 'two' }, dir .. '/a.txt')
  git('add', '.')
  git('commit', '-q', '-m', 'base')
  git('checkout', '-q', '-b', 'feature')
  vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/a.txt')
  git('commit', '-q', '-am', 'feature')
  vim.fn.writefile({ 'one', 'TWO', 'three' }, dir .. '/a.txt')
  vim.fn.mkdir(dir .. '/new dir', 'p')
  vim.fn.writefile({ 'fresh' }, dir .. '/new dir/b.txt')
  vim.fn.writefile({ 'ignored.txt' }, dir .. '/.gitignore')
  vim.fn.writefile({ 'ignored' }, dir .. '/ignored.txt')

  local cwd = vim.fn.getcwd()
  vim.fn.chdir(dir)
  local ok, err = pcall(fn, dir)
  vim.fn.chdir(cwd)
  vim.fn.delete(dir, 'rf')
  if not ok then
    error(err)
  end
end

T['resolve_scope finds the default branch and get_local_diff includes uncommitted changes'] = function()
  in_temp_repo(function(dir)
    local agent = require('ghlite.agent')
    local async = require('async')

    expect.equality(agent.root(), dir)
    local scope, diff = async
      .run(function()
        local resolved = agent.resolve_scope()
        return resolved, agent.get_local_diff(resolved)
      end)
      :wait(5000)

    -- No origin in this repository, so `main` is the first default that resolves.
    expect.equality(scope.base, 'main')
    expect.equality(#scope.merge_base, 40)
    expect.equality(diff:find('+++ b/a.txt', 1, true) ~= nil, true)
    expect.equality(diff:find('+TWO', 1, true) ~= nil, true)
    expect.equality(diff:find('+three', 1, true) ~= nil, true)
    -- Untracked files are included, ignored ones are not.
    expect.equality(diff:find('+++ b/new dir/b.txt', 1, true) ~= nil, true)
    expect.equality(diff:find('+fresh', 1, true) ~= nil, true)
    expect.equality(diff:find('+++ b/ignored.txt', 1, true), nil)
  end)
end

T['resolve_scope uses agent.base and falls back to HEAD'] = function()
  local agent = require('ghlite.agent')
  local config = require('ghlite.config')
  local async = require('async')

  local tried = {}
  local function run(fn)
    return async.run(fn):wait(1000)
  end
  with_overrides({
    ['ghlite.system'] = {
      run_result = function(cmd)
        table.insert(tried, cmd[3])
        if cmd[2] == 'rev-parse' then
          return { code = 0, stdout = 'abc\n' }
        end
        return { code = 1, stdout = '' }
      end,
    },
  }, function()
    config.s.agent.base = 'upstream/dev'
    local ok, scope = pcall(run, agent.resolve_scope)
    config.s.agent.base = nil
    assert(ok, scope)
    expect.equality(scope, { base = 'HEAD', merge_base = 'abc' })
  end)
  expect.equality(tried, { 'upstream/dev', 'HEAD' })
end

T['GHLitePRDiff shows local changes and draft diagnostics without a PR'] = function()
  in_temp_repo(function(dir)
    reset()
    local agent = require('ghlite.agent')
    local diff = require('ghlite.diff')
    local state = require('ghlite.state')
    agent.start(dir)
    agent.add_draft(dir, 'a.txt', 2, 2, 'Why upper case?')

    with_overrides({
      ['ghlite.pr_utils'] = {
        get_selected_pr = function()
          return nil
        end,
      },
      ['ghlite.gh'] = {
        get_pr_diff = function()
          error('local changes must not be fetched from GitHub')
        end,
      },
      ['ghlite.ui'] = {
        notify = function() end,
      },
    }, function()
      diff.load_pr_diff():wait(5000)
      vim.wait(1000, function()
        return #vim.diagnostic.get(state.diff_buffer_id) > 0
      end)
    end)

    local buf = state.diff_buffer_id
    expect.equality(state.diff_is_local, true)
    expect.equality(vim.api.nvim_buf_get_name(buf):find('Local Diff: main', 1, true) ~= nil, true)
    local diagnostics = vim.diagnostic.get(buf, { namespace = vim.api.nvim_create_namespace('GHLiteAgentNamespace') })
    expect.equality(#diagnostics, 1)
    expect.equality(vim.api.nvim_buf_get_lines(buf, diagnostics[1].lnum, diagnostics[1].lnum + 1, false)[1], '+TWO')

    -- The untracked file is mapped too, without the tab git appends to paths with spaces.
    expect.equality(state.filename_line_to_diff_line[dir .. '/new dir/b.txt'] ~= nil, true)

    vim.cmd('only')
    vim.api.nvim_buf_delete(buf, { force = true })
    agent.discard(dir)
    state.diff_is_local = false
  end)
end

T['export names the local scope when no PR is selected'] = function()
  reset()
  local agent = require('ghlite.agent')
  local export = require('ghlite.export')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Handle nil')

  local collected
  with_overrides(
    agent_overrides({
      ['ghlite.agent'] = {
        resolve_scope = function()
          return { base = 'origin/HEAD', merge_base = 'abcdef1234567890' }
        end,
      },
      ['ghlite.pr_utils'] = {
        get_selected_pr = function()
          return nil
        end,
      },
    }),
    function()
      collected = require('async')
        .run(function()
          return export.collect()
        end)
        :wait(1000)
    end
  )

  expect.equality(collected.scope, { base = 'origin/HEAD', merge_base = 'abcdef1234567890' })
  local markdown = require('ghlite.export_utils').render(collected, { intro = '', comment_hunk = false })
  expect.equality(
    markdown,
    table.concat({
      'Reviewing local changes against origin/HEAD (merge base abcdef1), including uncommitted changes and untracked files',
      '',
      '## Comments',
      '',
      '1. `lua/a.lua:2` - Handle nil',
      '',
    }, '\n')
  )
  agent.discard(root)
end

T['update_comment refuses to empty an agent draft'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Keep me')
  local bufnr = open_buffer('/repo/lua/a.lua', 2)

  with_overrides(
    agent_overrides({
      ['ghlite.utils'] = {
        get_comment = function(_, _, _, _, _, cb)
          cb('  \n')
        end,
      },
    }),
    function()
      comments.update_comment():wait(1000)
    end
  )

  expect.equality(agent.get(root).drafts[1].body, 'Keep me')
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

--- @param fn fun()
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

T['entering buffers without an agent review publishes no diagnostics'] = function()
  reset()
  local comments = require('ghlite.comments')
  local bufnr = open_buffer('/repo/lua/a.lua', 1)

  local changed = 0
  local autocmd = vim.api.nvim_create_autocmd('DiagnosticChanged', {
    callback = function()
      changed = changed + 1
    end,
  })
  with_immediate_schedule(function()
    with_overrides(agent_overrides(), function()
      comments.load_comments_on_buffer(bufnr)
      comments.load_comments_on_buffer(bufnr)
    end)
  end)
  vim.api.nvim_del_autocmd(autocmd)

  expect.equality(changed, 0)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['refresh_agent_drafts redraws drafts in codediff buffers'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  package.loaded['codediff.core.virtual_file'] = nil
  state.selected_PR = { number = 12, headRefOid = 'abcdef1234567890' }
  agent.start(root)
  local bufnr = open_buffer('codediff:////repo///abcdef12345/lua/a.lua', 1)
  local namespace = vim.api.nvim_create_namespace('GHLiteAgentNamespace')

  local function refresh()
    with_immediate_schedule(function()
      with_overrides(
        agent_overrides({
          ['ghlite.pr_utils'] = {
            get_selected_pr = function()
              return state.selected_PR
            end,
          },
        }),
        function()
          comments.refresh_agent_drafts()
          -- Resolving the codediff file runs in a task; let it finish.
          vim.wait(200, function()
            return false
          end, 10)
        end
      )
    end)
  end

  local draft = agent.add_draft(root, 'lua/a.lua', 3, 3, 'In codediff')
  refresh()
  expect.equality(#vim.diagnostic.get(bufnr, { namespace = namespace }), 1)

  agent.delete_draft(root, draft.id)
  refresh()
  expect.equality(#vim.diagnostic.get(bufnr, { namespace = namespace }), 0)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['refresh_agent_drafts leaves diffview buffers outside the current view alone'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  agent.start(root)
  local diffview_buf = open_buffer('diffview:///repo/.git/abc/lua/a.lua', 1)
  local file_buf = open_buffer('/repo/lua/a.lua', 1)

  local resolved = 0
  package.loaded['diffview.lib'] = {
    get_current_view = function()
      resolved = resolved + 1
      -- Diffview lives in another tab page.
      return nil
    end,
  }
  local errors = {}
  with_immediate_schedule(function()
    with_overrides(
      agent_overrides({
        ['ghlite.ui'] = {
          notify = function(message, level)
            if level == vim.log.levels.ERROR then
              table.insert(errors, message)
            end
          end,
        },
      }),
      function()
        agent.add_draft(root, 'lua/a.lua', 2, 2, 'Draft')
        comments.refresh_agent_drafts()
        vim.wait(100, function()
          return false
        end, 10)
        -- Entering the diffview buffer resolves it, and a missing view is not an error.
        comments.load_comments_on_buffer(diffview_buf)
        vim.wait(100, function()
          return false
        end, 10)
      end
    )
  end)
  package.loaded['diffview.lib'] = nil

  expect.equality(errors, {})
  expect.equality(resolved, 1)
  local namespace = vim.api.nvim_create_namespace('GHLiteAgentNamespace')
  expect.equality(#vim.diagnostic.get(file_buf, { namespace = namespace }), 1)
  vim.api.nvim_buf_delete(diffview_buf, { force = true })
  vim.api.nvim_buf_delete(file_buf, { force = true })
end

T['delete_comment offers own GitHub comments next to agent drafts'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  agent.start(root)
  agent.add_draft(root, 'lua/a.lua', 2, 2, 'Draft')
  state.comments_list = {
    ['/repo/lua/a.lua'] = {
      {
        id = 55,
        line = 2,
        content = 'x',
        comments = {
          { id = 55, user = 'me', body = 'Published', updated_at = 'now', diff_hunk = '@@' },
          { id = 56, user = 'alice', body = 'Not mine', updated_at = 'now', diff_hunk = '@@' },
        },
      },
    },
  }
  local bufnr = open_buffer('/repo/lua/a.lua', 2)

  local offered
  local deleted
  with_overrides(
    agent_overrides({
      ['ghlite.gh'] = {
        get_user = function()
          return 'me'
        end,
        delete_comment = function(id)
          deleted = id
        end,
      },
      ['ghlite.ui'] = {
        select = function(items, opts)
          offered = vim.tbl_map(opts.format_item, items)
          return items[2]
        end,
      },
    }),
    function()
      comments.delete_comment():wait(1000)
    end
  )

  expect.equality(offered, { '[agent] Draft', 'now: Published' })
  expect.equality(deleted, 55)
  expect.equality(#agent.get(root).drafts, 1)
  state.comments_list = {}
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['the local diff shows no review threads of a PR loaded earlier'] = function()
  reset()
  local comments = require('ghlite.comments')
  local state = require('ghlite.state')
  local bufnr = vim.api.nvim_create_buf(false, true)
  state.diff_is_local = true
  state.comments_list = { ['/repo/lua/a.lua'] = { { line = 2, content = 'Old thread', comments = { { id = 1 } } } } }
  state.filename_line_to_diff_line = { ['/repo/lua/a.lua'] = { [2] = 5 } }

  with_immediate_schedule(function()
    with_overrides(agent_overrides(), function()
      comments.load_comments_on_diff_buffer(bufnr)
    end)
  end)

  expect.equality(vim.diagnostic.get(bufnr), {})
  state.comments_list = {}
  reset()
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T['drafts follow edits in their buffer and keep the new lines once it is written'] = function()
  reset()
  local agent = require('ghlite.agent')
  local comments = require('ghlite.comments')
  local dir = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(dir .. '/lua', 'p')
  local filename = dir .. '/lua/a.lua'
  vim.fn.writefile({ 'one', 'two', 'three', 'four' }, filename)
  agent.start(dir)
  agent.add_draft(dir, 'lua/a.lua', 2, 3, 'Range')
  agent.add_draft(dir, 'lua/a.lua', 4, 4, 'Last line')

  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  local bufnr = vim.api.nvim_get_current_buf()
  local namespace = vim.api.nvim_create_namespace('GHLiteAgentNamespace')
  local function draft_diagnostic_lines()
    return vim.tbl_map(function(d)
      return d.lnum + 1
    end, vim.diagnostic.get(bufnr, { namespace = namespace }))
  end

  local overrides = {
    ['ghlite.agent'] = {
      root = function()
        return dir
      end,
    },
  }
  with_immediate_schedule(function()
    with_overrides(overrides, function()
      comments.load_comments_on_buffer(bufnr)
      expect.equality(draft_diagnostic_lines(), { 3, 4 })

      -- Two lines inserted above both drafts.
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'new 1', 'new 2' })
      comments.load_comments_on_buffer(bufnr)
      expect.equality(draft_diagnostic_lines(), { 5, 6 })

      -- Unsaved edits do not touch the session: the agent reads the file on disk.
      agent.reset_cache()
      expect.equality(agent.get(dir).drafts[1].line, 3)

      vim.cmd('write')
      -- What the BufWritePost autocmd from setup() does.
      comments.save_agent_anchors(bufnr)
    end)
  end)

  agent.reset_cache()
  local drafts = agent.get(dir).drafts
  expect.equality({ drafts[1].start_line, drafts[1].line }, { 4, 5 })
  expect.equality({ drafts[2].start_line, drafts[2].line }, { 6, 6 })

  -- Reloading from disk replaces every line, so the anchors start over from the saved lines.
  with_immediate_schedule(function()
    with_overrides(overrides, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { 'unsaved' })
      vim.cmd('edit!')
      comments.forget_agent_anchors(bufnr)
      comments.load_comments_on_buffer(bufnr)
      expect.equality(draft_diagnostic_lines(), { 5, 6 })
    end)
  end)

  vim.api.nvim_buf_delete(bufnr, { force = true })
  agent.discard(dir)
  vim.fn.delete(dir, 'rf')
end

return T
