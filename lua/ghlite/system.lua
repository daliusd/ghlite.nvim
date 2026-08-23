-- Boundary module for external command execution.

local async = require('async')
local config = require('ghlite.config')
local ui = require('ghlite.ui')

local M = {}

--- Run a command given as a space-separated string.
--- @async
--- @param cmd string
--- @return string stdout
--- @return string stderr
function M.run_str(cmd)
  local cmd_split = vim.split(cmd, ' ')
  local result = async.await(3, vim.system, cmd_split, { text = true })
  if #result.stderr > 0 then
    config.log('system.run_str error', result.stderr)
    ui.notify(result.stderr, vim.log.levels.ERROR)
  end

  return result.stdout, result.stderr
end

--- Run a command given as an argument list.
--- @async
--- @param cmd string[]
--- @return string stdout
function M.run(cmd)
  local result = async.await(3, vim.system, cmd, { text = true })
  return result.stdout
end

--- Run a command synchronously and return its result.
--- @param cmd string[]
--- @param opts table|nil
function M.run_sync(cmd, opts)
  return vim.system(cmd, opts):wait()
end

--- Run an arbitrary command string through the shell asynchronously.
--- Unlike `run_str`, this preserves quoting and supports pipes/redirects, so
--- it is used for user-configured commands rather than fixed git/gh calls.
--- @async
--- @param cmd string
--- @param opts table|nil e.g. `{ cwd = string }`
--- @return string stdout
--- @return string stderr
function M.run_shell(cmd, opts)
  local sys_opts = vim.tbl_extend('force', { text = true }, opts or {})
  local result = async.await(3, vim.system, { 'sh', '-c', cmd }, sys_opts)
  if #result.stderr > 0 then
    config.log('system.run_shell error', result.stderr)
  end

  return result.stdout, result.stderr
end

return M
