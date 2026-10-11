local M = {}

M.s = {
  debug = false,
  view_split = 'vsplit',
  diff_split = 'vsplit',
  diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto'
  comment_split = 'split',
  comment_hunk = true,
  comments_quickfix = 'fill', -- 'jump', 'fill' or false
  open_command = 'open',
  refresh_interval = 0, -- seconds between background refreshes of PR list, PR view and comments; 0 disables
  merge = {
    approved = '--squash',
    nonapproved = '--auto --squash',
  },
  html_comments_command = { 'lynx', '-stdin', '-dump' },
  default_review = 'github', -- review GHLitePRStartReview starts without an argument: 'github' or 'agent'
  agent = {
    base = nil, -- ref local changes are compared against without a PR; nil tries origin/HEAD, origin/main, origin/master, main, master
    intro = 'I reviewed your code and have the following comments. Please address them.', -- false to leave it out
    output = 'clipboard', -- 'clipboard', 'buffer' or function(markdown, export)
    github_threads = 'unresolved', -- review threads to export: 'unresolved', 'all' or false
    github_comments = true, -- export review summaries and PR conversation comments
    exclude_authors = {}, -- logins whose comments are left out, e.g. noisy bots
  },
  pr_commands = {
    {
      name = 'AI Review',
      cmd = 'pi -p "review this PR"',
      key = 'cr',
    },
  },
  keymaps = {
    diff = {
      open_file = 'gf',
      open_file_tab = '',
      open_file_split = 'o',
      open_file_vsplit = 'O',
      approve = 'cA',
      request_changes = 'cR',
    },
    comment = {
      send_comment = 'c<CR>',
      resolve = 'cS',
      unresolve = 'cU',
    },
    pr = {
      approve = 'cA',
      request_changes = 'cR',
      merge = 'cM',
      comment = 'ca',
      diff = 'cp',
      diffview = 'cl',
      checkout = 'co',
      refresh = 'r',
      open_commit = 'cs',
      toggle_viewed = 'cv',
      export = 'ce',
    },
    commit = {
      open_file = 'gf',
      open_file_split = 'o',
      open_file_vsplit = 'O',
      diff = 'cp',
      next_commit = ']c',
      prev_commit = '[c',
      yank_sha = 'y',
      open_in_browser = 'gx',
      refresh = 'r',
      close = 'q',
    },
  },
}

function M.setup(config)
  M.s = vim.tbl_deep_extend('force', {}, M.s, config)
end

function M.log(key, message)
  if M.s.debug then
    local home = os.getenv('HOME')
    local log_file_name = home .. '/.ghlite.log'
    local log_file = io.open(log_file_name, 'a')
    if log_file then
      log_file:write(os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. key .. ':\n')
      log_file:write(vim.inspect(message))
      log_file:write('\n\n')
      log_file:close()
    end
  end
end

return M
