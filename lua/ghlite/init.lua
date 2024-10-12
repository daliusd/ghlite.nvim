local config = require "ghlite.config"
local comments = require "ghlite.comments"
local diff = require "ghlite.diff"

local M = {}

M.setup = function(user_config)
  config.setup(user_config)

  vim.api.nvim_create_user_command(
    'GHLitePRLoadComments',
    comments.load_comments,
    {}
  )

  vim.api.nvim_create_user_command(
    'GHLitePRDiff',
    diff.load_pr_diff,
    {}
  )

  vim.api.nvim_create_user_command(
    'GHLitePRAddComment',
    comments.comment_on_line,
    {}
  )

  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*",
    callback = function(args)
      comments.load_comments_on_buffer(args.buf)
    end
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*",
    callback = function(args)
      comments.load_comments_on_buffer(args.buf)
    end
  })
end

return M