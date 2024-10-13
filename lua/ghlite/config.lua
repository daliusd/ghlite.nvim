local M = {}

M.debug = false
M.diff_split = 'vsplit'
M.comment_split = 'split'
M.open_command = 'open'

function M.setup(config)
  if config.debug ~= nil then
    M.debug = config.debug
  end

  if config.diff_split ~= nil then
    M.diff_split = config.diff_split
  end

  if config.comment_split ~= nil then
    M.comment_split = config.comment_split
  end

  if config.open_command ~= nil then
    M.open_command = config.open_command
  end
end

function M.log(key, message)
  if M.debug then
    local home = os.getenv("HOME")
    local log_file_name = home .. '/.ghlite.log'
    local log_file = io.open(log_file_name, "a")
    if log_file then
      log_file:write(vim.fn.strftime("%Y-%m-%d %H:%M:%S") .. ' ' .. key .. ':\n')
      log_file:write(vim.inspect(message))
      log_file:write('\n\n')
      log_file:close();
    end
  end
end

return M
