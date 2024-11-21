local M = {
}

M.s = {
  debug = false,
  view_split = 'vsplit',
  diff_split = 'vsplit',
  comment_split = 'split',
  open_command = 'open',
  merge = {
    approved = '--squash',
    nonapproved = '--auto --squash',
  },
  html_comments_command = { 'lynx', '-stdin', '-dump' },
  keymaps = {
    diff = {
      open_file = 'gf',
      open_file_tab = 'gt',
      open_file_split = 'gs',
      open_file_vsplit = 'gv',
      approve = '<C-A>',
    },
    comment = {
      send_comment = '<C-CR>'
    },
    pr = {
      approve = '<C-A>',
      merge = '<C-M>',
      comment = '<C-N>',
    },
  },
}

function M.setup(config)
  M.s = vim.tbl_deep_extend("force", {}, M.s, config)
end

function M.log(key, message)
  if M.s.debug then
    local home = os.getenv("HOME")
    local log_file_name = home .. '/.ghlite.log'
    local log_file = io.open(log_file_name, "a")
    if log_file then
      log_file:write(os.date("%Y-%m-%d %H:%M:%S") .. ' ' .. key .. ':\n')
      log_file:write(vim.inspect(message))
      log_file:write('\n\n')
      log_file:close();
    end
  end
end

return M
