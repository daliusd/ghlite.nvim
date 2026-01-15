# ghlite.nvim - Agent Development Guide

This file provides essential information for AI coding agents working on ghlite.nvim, a Neovim plugin for GitHub PR management.

## Project Overview

- **Type**: Neovim plugin written in Lua
- **Purpose**: Augment GitHub PR review workflow in Neovim using `gh` CLI
- **Requirements**: Neovim 0.10+, GitHub CLI (`gh`)
- **Optional Dependencies**: Diffview.nvim or CodeDiff.nvim for enhanced diff viewing

## Build/Lint/Test Commands

### Formatting
```bash
# Format all Lua files with StyLua
stylua .

# Check formatting (dry run)
stylua --check .
```

### Manual Testing
This plugin does not have automated tests. Manual testing is required:
1. Install the plugin in Neovim
2. Navigate to a git repository with GitHub PRs
3. Test commands like `:GHLitePRSelect`, `:GHLitePRDiff`, etc.
4. Verify GitHub CLI integration works correctly

### Debugging
Enable debug mode in config:
```lua
require('ghlite').setup({ debug = true })
```
This writes debug information to `~/.ghlite.log`

## Code Style Guidelines

### Formatting (StyLua Configuration)
- **Column width**: 120 characters
- **Indentation**: 2 spaces (never tabs)
- **Line endings**: Unix (LF)
- **Quote style**: Auto-prefer single quotes
- **Call parentheses**: Always use parentheses for function calls
- **Require sorting**: Enabled (requires are sorted alphabetically)

### Module Structure
```lua
-- 1. Requires at top (sorted alphabetically by StyLua)
local comments = require('ghlite.comments')
local config = require('ghlite.config')
local utils = require('ghlite.utils')

-- 2. Module table
local M = {}

-- 3. Local/private functions
local function private_helper()
  -- implementation
end

-- 4. Public functions
function M.public_function()
  -- implementation
end

-- 5. Return module
return M
```

### Imports
- Always use `local` for requires
- Place all requires at the top of the file
- StyLua will automatically sort requires alphabetically
- Use relative requires within the plugin: `require('ghlite.module_name')`

### Type Annotations
Use LuaLS annotations for type safety:
```lua
--- @class Comment
--- @field id number
--- @field url string
--- @field path string

--- @type PullRequest|nil
M.selected_PR = nil

--- @param number number
function M.checkout_pr(number, cb)
  -- implementation
end
```

### Naming Conventions
- **Modules**: lowercase with underscores (e.g., `pr_commands.lua`, `comments_utils.lua`)
- **Variables**: lowercase with underscores (e.g., `selected_pr`, `diff_buffer_id`)
- **Functions**: lowercase with underscores (e.g., `load_pr_view`, `get_current_pr`)
- **Constants**: uppercase with underscores (rare in this codebase)
- **Private functions**: prefix with `local function` (e.g., `local function ui_selectPR`)

### Function Definitions
```lua
-- Module functions (exported)
function M.load_comments()
  -- implementation
end

-- Local/private functions
local function parse_or_default(str, default)
  -- implementation
end

-- Arrow-style functions for callbacks
local function open_file_from_diff(open_command)
  return function()
    -- implementation
  end
end
```

### String Formatting
Use `string.format` (aliased as `f`) for complex strings:
```lua
local f = string.format

-- Good
local cmd = f('gh pr view %s --json url,author', pr_number)
local text = f('#%s: %s (%s)', pr.number, pr.title, pr.author.login)

-- Also acceptable for simple cases
local path = git_root .. '/' .. filename
```

### Asynchronous Operations
Use callbacks (not promises/async-await):
```lua
function M.get_current_pr(cb)
  utils.system_str_cb('gh pr view --json ...', function(result, stderr)
    cb(parse_or_default(result, nil))
  end)
end

-- Usage
M.get_current_pr(function(pr)
  if pr == nil then
    return
  end
  -- do something with pr
end)
```

### Error Handling
- Check for `nil` values before use
- Use `vim.notify` with appropriate log levels for user-facing errors
- Use `config.log()` for debug information when `debug = true`
- Always handle stderr in system calls

```lua
-- Good error handling
if checked_out_pr == nil then
  utils.notify('No PR to work with.', vim.log.levels.WARN)
  return
end

-- Log errors from system calls
if #result.stderr > 0 then
  config.log('system_str_cb error', result.stderr)
  M.notify(result.stderr, vim.log.levels.ERROR)
end
```

### vim.schedule Usage
Always wrap UI operations in `vim.schedule`:
```lua
vim.schedule(function()
  vim.ui.select(prs, options, callback)
end)

vim.schedule(function()
  local current_buffer = vim.api.nvim_get_current_buf()
  M.load_comments_on_buffer(current_buffer)
end)
```

### Configuration Access
- Global config stored in `config.s` (not `config.config`)
- Use `vim.tbl_deep_extend` for merging configs
- Access config values: `config.s.debug`, `config.s.view_split`, etc.

### Buffer and Window Management
```lua
-- Create buffers
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].buftype = 'nofile'
vim.bo[buf].filetype = 'markdown'

-- Set buffer content
vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)

-- Keymaps
vim.api.nvim_buf_set_keymap(buf, 'n', 'gf', '', {
  noremap = true,
  silent = true,
  callback = function_name
})
```

## Git Workflow

### Commit Message Style
Follow conventional commits format:
- `feat:` for new features (e.g., "feat: add review comments to GHLitePRView command")
- `fix:` for bug fixes (e.g., "fix: improve error handling and notification messages")
- `refactor:` for code refactoring (e.g., "refactor: update PR comment keybinding")
- `docs:` for documentation (e.g., "docs: update comments for split options")
- `chore:` for maintenance tasks (e.g., "chore: get_diffview_filename logging added")

### Pull Requests
Include PR numbers in commit messages when merging: `feat: add feature (#17)`

## Key Files and Their Purposes

- `lua/ghlite/init.lua` - Plugin entry point, sets up commands and autocommands
- `lua/ghlite/config.lua` - Configuration management and debug logging
- `lua/ghlite/state.lua` - Global state (selected PR, comments, buffer mappings)
- `lua/ghlite/gh.lua` - GitHub CLI wrapper functions
- `lua/ghlite/pr_commands.lua` - PR selection, checkout, view, approve, merge
- `lua/ghlite/comments.lua` - Comment loading, display, and management
- `lua/ghlite/diff.lua` - PR diff viewing and navigation
- `lua/ghlite/utils.lua` - Utility functions (system calls, git operations, UI helpers)
- `lua/ghlite/types.lua` - LuaLS type definitions

## Common Patterns

### System Command Execution
```lua
-- Simple command with callback
utils.system_str_cb('gh pr view --json ...', function(result, stderr)
  -- handle result
end)

-- Command with array args (for complex commands)
local request = { 'gh', 'api', '--method', 'POST', ... }
utils.system_cb(request, function(result)
  -- handle result
end)
```

### JSON Parsing with Fallback
```lua
local function parse_or_default(str, default)
  local success, result = pcall(vim.json.decode, str)
  if success then
    return result
  end
  return default
end
```

### User Selection UI
```lua
vim.ui.select(items, {
  prompt = 'Select item:',
  format_item = function(item)
    return string.format('%s: %s', item.id, item.name)
  end,
}, function(selected)
  if selected ~= nil then
    -- handle selection
  end
end)
```

## Important Notes for Agents

- This plugin has NO automated tests - manual testing is essential
- All GitHub operations go through `gh` CLI, not direct API calls
- The plugin supports both "quick review" (without checkout) and "thorough review" (with checkout) workflows
- State is managed globally in `state.lua` - be careful with state mutations
- Use `config.log()` liberally for debugging - it only writes when `debug = true`
- Always handle the case where `gh` might not be configured or repo has no PRs
