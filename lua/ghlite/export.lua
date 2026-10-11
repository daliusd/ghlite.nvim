-- Export review comments as markdown for coding agents.

local agent = require('ghlite.agent')
local comments = require('ghlite.comments')
local config = require('ghlite.config')
local export_utils = require('ghlite.export_utils')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local system = require('ghlite.system')
local task = require('ghlite.task')
local ui = require('ghlite.ui')
local utils = require('ghlite.utils')

require('ghlite.types')

local M = {}

--- Render comment bodies to text concurrently: each HTML body runs `html_comments_command`.
--- @async
--- @param bodies string[]
--- @return string[]
local function bodies_to_text(bodies)
  return system.map_parallel(bodies, utils.html_to_text_async)
end

--- Gather the agent session's drafts plus the selected PR's review summaries,
--- conversation comments and review threads.
--- @async
--- @param summary string|nil
--- @return ExportData
function M.collect(summary)
  local agent_config = config.s.agent
  local session = agent.current()
  --- @type ExportData
  local export = {
    summary = summary,
    drafts = session and session.drafts or {},
    reviews = {},
    pr_comments = {},
    threads = {},
  }

  local selected_pr = pr_utils.get_selected_pr(true)
  if selected_pr == nil then
    if session ~= nil then
      export.scope = agent.resolve_scope()
    end
    return export
  end

  local pr_info = gh.get_pr_info(selected_pr.number)
  export.pr = {
    number = selected_pr.number,
    title = pr_info and pr_info.title or selected_pr.title,
    url = pr_info and pr_info.url,
    head = selected_pr.headRefOid,
  }

  if agent_config.github_comments and pr_info ~= nil then
    export.reviews = export_utils.collect_notes(pr_info.reviews, agent_config.exclude_authors, bodies_to_text)
    export.pr_comments = export_utils.collect_notes(pr_info.comments, agent_config.exclude_authors, bodies_to_text)
  end

  if agent_config.github_threads then
    comments.load_comments_only(selected_pr.number)
    export.threads = export_utils.collect_threads(state.comments_list, utils.get_git_root(), {
      threads = agent_config.github_threads,
      exclude_authors = agent_config.exclude_authors,
    })
  end

  return export
end

--- @param markdown string
local function open_in_buffer(markdown)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'GHLite export (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')')
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, '\n', { trimempty = true }))
  if not utils.is_empty(config.s.view_split) then
    vim.api.nvim_command(config.s.view_split)
  end
  vim.api.nvim_set_current_buf(buf)
end

--- Hand the markdown to the configured `agent.output`.
--- @async
--- @param markdown string
--- @param export ExportData
local function send_output(markdown, export)
  ui.schedule()
  local output = config.s.agent.output
  if type(output) == 'function' then
    output(markdown, export)
  elseif output == 'buffer' then
    open_in_buffer(markdown)
  else
    vim.fn.setreg('"', markdown)
    local ok = pcall(vim.fn.setreg, '+', markdown)
    ui.notify(ok and 'Review exported to clipboard.' or 'Review exported to the unnamed register.')
  end
end

--- Render `export` and send it to the configured output.
--- @async
--- @param export ExportData
--- @return boolean exported false when there was nothing to export
function M.send(export)
  if export_utils.is_empty(export) then
    ui.notify('Nothing to export.', vim.log.levels.WARN)
    return false
  end
  local markdown = export_utils.render(export, {
    intro = config.s.agent.intro,
    comment_hunk = config.s.comment_hunk,
  })
  send_output(markdown, export)
  return true
end

function M.export_comments()
  return task.run(function()
    ui.notify('Comment export started...')
    M.send(M.collect())
  end)
end

return M
