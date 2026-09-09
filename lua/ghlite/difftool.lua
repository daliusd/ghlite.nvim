local state = require('ghlite.state')
local system = require('ghlite.system')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

local M = {}
local worktrees = {}
local cleanup_registered = false

local function register_cleanup()
  if cleanup_registered then
    return
  end
  cleanup_registered = true
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('GHLiteDifftoolCleanup', { clear = true }),
    callback = function()
      for _, worktree in ipairs(worktrees) do
        vim.fn.system({ 'git', '-C', worktree.git_root, 'worktree', 'remove', '--force', worktree.path })
      end
    end,
  })
end

--- Load Neovim's optional built-in difftool package.
--- @return boolean
function M.ensure_loaded()
  pcall(vim.cmd, 'packadd nvim.difftool')
  return vim.fn.exists(':DiffTool') == 2
end

--- Open two Git revisions using Neovim's built-in :DiffTool.
--- Git worktrees provide the directories required by the built-in tool.
--- @async
--- @param left string
--- @param right string
--- @param use_working_tree boolean|nil use the current checkout as the right side
--- @return boolean
function M.open_revisions(left, right, use_working_tree)
  -- task.run resumes coroutines in a libuv fast event after awaits. Both
  -- :packadd and tempname are Vimscript operations, so enter the main loop.
  ui.schedule()

  if not M.ensure_loaded() then
    ui.notify('Neovim built-in difftool is unavailable (requires nvim.difftool).', vim.log.levels.ERROR)
    return false
  end

  local git_root = utils.get_git_root()
  -- get_git_root awaits vim.system and resumes this coroutine in a fast event.
  ui.schedule()
  local left_path = vim.fn.tempname()
  local right_path = use_working_tree and git_root or vim.fn.tempname()
  local function add_worktree(path, revision)
    local result = system.run_result({ 'git', '-C', git_root, 'worktree', 'add', '--detach', path, revision })
    return result.code == 0
  end

  local left_added = add_worktree(left_path, left)
  local right_added = use_working_tree or (left_added and add_worktree(right_path, right))

  -- `add_worktree` awaits vim.system, which resumes in a fast event context.
  ui.schedule()

  if not left_added or not right_added then
    vim.fn.system({ 'git', '-C', git_root, 'worktree', 'remove', '--force', left_path })
    if not use_working_tree then
      vim.fn.system({ 'git', '-C', git_root, 'worktree', 'remove', '--force', right_path })
    end
    ui.notify('Unable to create temporary worktrees for the diff.', vim.log.levels.ERROR)
    return false
  end

  table.insert(worktrees, { git_root = git_root, path = left_path })
  if not use_working_tree then
    table.insert(worktrees, { git_root = git_root, path = right_path })
    -- Review comments belong to the PR head, which is the right-hand worktree.
    state.difftool_paths[right_path] = git_root
  end
  register_cleanup()
  vim.schedule(function()
    require('difftool').open(left_path, right_path)
  end)
  return true
end

return M
