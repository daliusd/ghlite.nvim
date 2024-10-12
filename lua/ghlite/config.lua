local M = {}

M.config = {}

function M.setup(config)
  M.config = config
end

function M.log(key, message)
  if M.config.debug then
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
