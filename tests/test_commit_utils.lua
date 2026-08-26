local T = MiniTest.new_set()
local expect = MiniTest.expect

local function reset_comments()
  local state = require('ghlite.state')
  state.comments_list = {}
end

--- @return integer|nil index of the first line equal to `needle`
local function index_of(lines, needle)
  for idx, line in ipairs(lines) do
    if line == needle then
      return idx
    end
  end
  return nil
end

local function has_line(lines, needle)
  return index_of(lines, needle) ~= nil
end

local function commit_fixture(overrides)
  local commit = {
    sha = 'abc1234def5678901234567890123456789abcde',
    html_url = 'https://github.test/commit/abc1234',
    commit = {
      message = 'feat: add commit view\n\nLonger explanation.',
      author = { name = 'Alice', email = 'alice@example.com', date = '2026-08-19T10:00:00Z' },
      committer = { name = 'Alice', email = 'alice@example.com', date = '2026-08-19T10:00:00Z' },
    },
    author = { login = 'alice' },
    committer = { login = 'alice' },
    parents = { { sha = '1111111222222222222222222222222222222222' } },
    stats = { additions = 12, deletions = 3, total = 15 },
    files = {
      {
        filename = 'lua/example.lua',
        status = 'modified',
        additions = 12,
        deletions = 3,
        patch = '@@ -1,2 +1,3 @@\n context\n-removed\n+added\n+more',
      },
    },
  }

  return vim.tbl_deep_extend('force', commit, overrides or {})
end

T['format_commits lists commits and maps their lines to indexes'] = function()
  local commit_utils = require('ghlite.commit_utils')

  local lines, index_by_line = commit_utils.format_commits({
    {
      oid = 'abc1234def5678',
      messageHeadline = 'first commit',
      committedDate = '2026-08-19T10:00:00Z',
      authors = { { login = 'alice', name = 'Alice' } },
    },
    {
      oid = 'fed4321cba8765',
      messageHeadline = 'second commit',
      committedDate = '2026-08-20T10:00:00Z',
      authors = { { name = 'Bob' } },
    },
  })

  expect.equality(lines, {
    '',
    '## Commits',
    '',
    '    abc1234  first commit (alice, 2026-08-19)',
    '    fed4321  second commit (Bob, 2026-08-20)',
  })
  expect.equality(index_by_line, { [4] = 1, [5] = 2 })
end

T['format_commits reports an empty commit list'] = function()
  local commit_utils = require('ghlite.commit_utils')

  local lines, index_by_line = commit_utils.format_commits({})

  expect.equality(lines[#lines], '    No commits found.')
  expect.equality(index_by_line, {})
end

T['format_commits truncates long headlines'] = function()
  local commit_utils = require('ghlite.commit_utils')

  local lines = commit_utils.format_commits({
    {
      oid = 'abc1234def5678',
      messageHeadline = string.rep('x', 100),
      committedDate = '2026-08-19T10:00:00Z',
      authors = { { login = 'alice' } },
    },
  })

  expect.equality(lines[4], '    abc1234  ' .. string.rep('x', 69) .. '... (alice, 2026-08-19)')
end

T['build_file_diff synthesizes headers the commits API omits'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(
    commit_utils.build_file_diff({
      filename = 'lua/new.lua',
      status = 'added',
      patch = '@@ -0,0 +1 @@\n+added',
    }),
    {
      'diff --git a/lua/new.lua b/lua/new.lua',
      '--- /dev/null',
      '+++ b/lua/new.lua',
      '@@ -0,0 +1 @@',
      '+added',
    }
  )

  expect.equality(
    commit_utils.build_file_diff({
      filename = 'lua/gone.lua',
      status = 'removed',
      patch = '@@ -1 +0,0 @@\n-gone',
    }),
    {
      'diff --git a/lua/gone.lua b/lua/gone.lua',
      '--- a/lua/gone.lua',
      '+++ /dev/null',
      '@@ -1 +0,0 @@',
      '-gone',
    }
  )

  expect.equality(
    commit_utils.build_file_diff({
      filename = 'lua/new_name.lua',
      previous_filename = 'lua/old_name.lua',
      status = 'renamed',
      patch = '@@ -1 +1 @@\n-old\n+new',
    })[1],
    'diff --git a/lua/old_name.lua b/lua/new_name.lua'
  )
end

T['format_checks summarizes runs and lists only the problems'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(commit_utils.format_checks(nil), {})
  expect.equality(commit_utils.format_checks({}), {})

  expect.equality(
    commit_utils.format_checks({
      { name = 'build', status = 'completed', conclusion = 'success' },
      { name = 'lint', status = 'completed', conclusion = 'skipped' },
      { name = 'test', status = 'completed', conclusion = 'failure' },
      { name = 'deploy', status = 'in_progress' },
    }),
    {
      'Checks: 2 passed, 1 failed, 1 pending',
      '    ✗ test (failure)',
      '    ⏳ deploy (in_progress)',
    }
  )
end

T['format_pr_checks renders and sorts check runs and legacy statuses'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(commit_utils.format_pr_checks(nil), {})
  expect.equality(commit_utils.format_pr_checks({}), {})
  expect.equality(
    commit_utils.format_pr_checks({
      { name = 'test', status = 'COMPLETED', conclusion = 'FAILURE', workflowName = 'CI' },
      { context = 'coverage', state = 'SUCCESS', description = 'Codecov' },
      { name = 'deploy', status = 'in_progress' },
      { context = 'required-review', state = 'PENDING' },
    }),
    {
      '',
      '## Checks',
      '',
      '    ✓ coverage — Codecov (SUCCESS)',
      '    ⏳ deploy (in_progress)',
      '    ⏳ required-review (PENDING)',
      '    ✗ test — CI (FAILURE)',
    }
  )
end

T['format_verification stays quiet for unsigned commits'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(commit_utils.format_verification(nil), nil)
  expect.equality(commit_utils.format_verification({ verified = false, reason = 'unsigned' }), nil)
  expect.equality(commit_utils.format_verification({ verified = true, reason = 'valid' }), 'Signature: verified')
  expect.equality(
    commit_utils.format_verification({ verified = false, reason = 'bad_signature' }),
    'Signature: unverified (bad_signature)'
  )
end

T['format_person falls back when the GitHub account is missing'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(commit_utils.format_person(nil, nil), 'unknown')
  expect.equality(
    commit_utils.format_person({ name = 'Alice', date = '2026-08-19T10:00:00Z' }, vim.NIL),
    'Alice at 2026-08-19T10:00:00Z'
  )
  expect.equality(
    commit_utils.format_person({ name = 'Alice', date = '2026-08-19T10:00:00Z' }, { login = 'alice' }),
    'Alice (alice) at 2026-08-19T10:00:00Z'
  )
end

T['format_commit_view renders header, files and a fenced diff'] = function()
  reset_comments()
  local commit_utils = require('ghlite.commit_utils')

  local lines, unmappable_lines = commit_utils.format_commit_view(commit_fixture(), nil, { pr_number = 42 })

  expect.equality(lines[1], 'abc1234 feat: add commit view')
  expect.equality(has_line(lines, 'SHA: abc1234def5678901234567890123456789abcde'), true)
  expect.equality(has_line(lines, 'Author: Alice (alice) at 2026-08-19T10:00:00Z'), true)
  -- committer matches the author, so it is not repeated
  expect.equality(has_line(lines, 'Committer: Alice (alice) at 2026-08-19T10:00:00Z'), false)
  expect.equality(has_line(lines, 'Parents: 1111111'), true)
  expect.equality(has_line(lines, 'PR: #42'), true)
  expect.equality(has_line(lines, 'Changes: 1 file changed, +12 -3'), true)
  expect.equality(has_line(lines, 'Longer explanation.'), true)
  expect.equality(has_line(lines, '    M lua/example.lua  +12 -3'), true)
  expect.equality(has_line(lines, '````diff'), true)
  expect.equality(lines[#lines], '````')

  -- the closing fence must not be treated as diff content
  expect.equality(unmappable_lines, { #lines })
end

T['format_commit_view marks merge commits and skips an absent diff'] = function()
  reset_comments()
  local commit_utils = require('ghlite.commit_utils')

  local commit = commit_fixture({
    parents = { { sha = '1111111aaa' }, { sha = '2222222bbb' } },
    files = {
      { filename = 'image.png', status = 'modified', additions = 0, deletions = 0 },
    },
  })

  local lines, unmappable_lines = commit_utils.format_commit_view(commit, nil, {})

  expect.equality(has_line(lines, 'Parents: 1111111, 2222222 (merge commit)'), true)
  expect.equality(has_line(lines, '    Diff not shown (binary or too large): image.png'), true)
  expect.equality(has_line(lines, '## Diff'), false)
  expect.equality(unmappable_lines, {})
end

T['format_commit_view includes review comments left on the commit'] = function()
  reset_comments()
  local state = require('ghlite.state')
  local commit_utils = require('ghlite.commit_utils')

  local sha = 'abc1234def5678901234567890123456789abcde'
  state.comments_list = {
    ['/repo/lua/example.lua'] = {
      {
        id = 1,
        line = 7,
        original_commit_id = sha,
        comments = {
          { user = 'bob', updated_at = 'now', body = 'On this commit' },
          { user = 'alice', updated_at = 'later', body = 'Replied' },
        },
      },
    },
    ['/repo/lua/other.lua'] = {
      {
        id = 2,
        line = 3,
        original_commit_id = 'another-sha',
        comments = { { user = 'carol', updated_at = 'now', body = 'On another commit' } },
      },
    },
  }

  local lines = commit_utils.format_commit_view(commit_fixture(), nil, {})
  reset_comments()

  expect.equality(has_line(lines, '## Review comments'), true)
  expect.equality(has_line(lines, '### example.lua:7'), true)
  expect.equality(has_line(lines, '✍️ bob at now:'), true)
  expect.equality(has_line(lines, 'On this commit'), true)
  expect.equality(has_line(lines, '✍️ alice replied at later:'), true)
  expect.equality(has_line(lines, 'On another commit'), false)
end

T['format_commit_view excludes comments that only carry the sha as commit_id'] = function()
  reset_comments()
  local state = require('ghlite.state')
  local commit_utils = require('ghlite.commit_utils')

  local sha = 'abc1234def5678901234567890123456789abcde'
  state.comments_list = {
    ['/repo/lua/example.lua'] = {
      {
        id = 1,
        line = 7,
        -- Written against an earlier commit, still applying to `sha` (the head).
        original_commit_id = 'earlier-sha',
        commit_id = sha,
        comments = { { user = 'bob', updated_at = 'now', body = 'Not on this commit' } },
      },
    },
  }

  local lines = commit_utils.format_commit_view(commit_fixture(), nil, {})
  reset_comments()

  expect.equality(has_line(lines, '## Review comments'), false)
  expect.equality(has_line(lines, 'Not on this commit'), false)
end

T['is_dev_null detects deleted-file diff paths'] = function()
  local commit_utils = require('ghlite.commit_utils')

  expect.equality(commit_utils.is_dev_null('/repo//dev/null'), true)
  expect.equality(commit_utils.is_dev_null('/dev/null'), true)
  expect.equality(commit_utils.is_dev_null('/repo/lua/example.lua'), false)
  expect.equality(commit_utils.is_dev_null(nil), false)
end

T['format_commit_view offers commit navigation only with a commit list'] = function()
  reset_comments()
  local commit_utils = require('ghlite.commit_utils')
  local config = require('ghlite.config')

  local without = commit_utils.format_commit_view(commit_fixture(), nil, {})
  local with = commit_utils.format_commit_view(commit_fixture(), nil, { commits = { {}, {} } })

  local function hints(lines)
    for _, line in ipairs(lines) do
      if line:find(config.s.keymaps.commit.open_file .. ': open file', 1, true) then
        return line
      end
    end
  end

  expect.equality(hints(without):find('next commit', 1, true), nil)
  expect.equality(hints(with):find('next commit', 1, true) ~= nil, true)
end

T['commit view lines map back to files through construct_mappings'] = function()
  reset_comments()
  local commit_utils = require('ghlite.commit_utils')
  local diff_utils = require('ghlite.diff_utils')

  local lines, unmappable_lines = commit_utils.format_commit_view(commit_fixture(), nil, {})
  local _, diff_line_to_filename_line = diff_utils.construct_mappings(lines, '/repo')
  for _, line_num in ipairs(unmappable_lines) do
    diff_line_to_filename_line[line_num] = nil
  end

  local added_line = index_of(lines, '+added')
  expect.equality(diff_line_to_filename_line[added_line], { '/repo/lua/example.lua', 2 })

  -- the closing fence was dropped from the mapping
  expect.equality(diff_line_to_filename_line[#lines], nil)
  -- header lines are before any file header and stay unmapped
  expect.equality(diff_line_to_filename_line[1], nil)
end

return T
