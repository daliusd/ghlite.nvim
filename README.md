# ghlite.nvim

Neovim plugin to work GitHub PRs quickly.

Main idea of this plugin to have tools that augment GitHub PR review using web
instead of replacing it like other plugins do.

[![ghlite.nvim intro](https://img.youtube.com/vi/TwzA3bhLrE4/0.jpg)](https://www.youtube.com/watch?v=TwzA3bhLrE4)

## Requirements

- nvim 0.10+

- [GitHub CLI (gh)](https://cli.github.com/)

- If you are using fzf-lua or telescope you might want to checkout how to
  override UI select. E.g. `vim.cmd('FzfLua register_ui_select')`

- [Diffview.nvim](https://github.com/sindrets/diffview.nvim) (optional)

## Installation

Using lazyvim.

NOTE: default config here. You can skip all the settings if you are OK with defaults.

```lua
  {
    'daliusd/ghlite.nvim',
    config = function()
      require('ghlite').setup({
        debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
        view_split = 'vsplit', -- set to empty string '' to open in active buffer
        diff_split = 'vsplit', -- set to empty string '' to open in active buffer
        comment_split = 'split', -- set to empty string '' to open in active buffer
        open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
        merge = {
          approved = '--squash',
          nonapproved = '--auto --squash',
        },
        keymaps = { -- override default keymaps with the ones you prefer
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
      })
    end,
    keys = {
      { '<leader>us', ':GHLitePRSelect<cr>',        silent = true },
      { '<leader>uo', ':GHLitePRCheckout<cr>',      silent = true },
      { '<leader>uv', ':GHLitePRView<cr>',          silent = true },
      { '<leader>uu', ':GHLitePRLoadComments<cr>',  silent = true },
      { '<leader>up', ':GHLitePRDiff<cr>',          silent = true },
      { '<leader>ul', ':GHLitePRDiffview<cr>',      silent = true },
      { '<leader>ua', ':GHLitePRAddComment<cr>',    silent = true },
      { '<leader>ua', ':GHLitePRAddComment<cr>',    mode = 'v',   silent = true },
      { '<leader>uc', ':GHLitePRUpdateComment<cr>', silent = true },
      { '<leader>ud', ':GHLitePRDeleteComment<cr>', silent = true },
      { '<leader>ug', ':GHLitePROpenComment<cr>',   silent = true },
    }
  }
```

## PR Review using ghlite.nvim

### Quick PR review

If you want to make quick PR review without checking out PR code to your repo
you can do it this way:

- Run `:GHLitePRSelect` and select PR you want to review. PR view will open.
  You can open `:GHLitePRView` anytime later to refresh/reopen PR view.

- Run `:GHLitePRDiff` to see diff of PR so you could review it in single
  window. Comments that can be displayed in diff view are loaded as well as
  diagnostics. Navigate comments using `vim.diagnostic.jump` or
  `vim.diagnostic.goto_\*` functions (latter is for older neovim versions) or
  keys you have mapped to those functions.

- Run `:GHLitePRAddComment` to comment in existing conversations or start the
  new one directly in diff view. Alternatively you can use
  `:GHLitePROpenComment` to open comments in browser.

- Run `:GHLitePRApprove` to approve PR if everything is OK. you can use
  `Ctrl-a` in diff and pr views.

### Thorough PR review

However it might be that you want to make thorough PR review by looking not
only at diff, but at surrounding code as well.

- Run `:GHLitePRSelect` or `:GHLitePRCheckout` and select PR you want to
  review. PR view will open. You can open `:GHLitePRView` anytime later to
  refresh/reopen PR view. You can skip this step if you have locally branch
  checked out that is related to PR. In that case plugin will resolve PR
  number from git branch.

- Run `:GHLitePRDiff` to see diff of PR so you could review it in single
  window. Use `gf` in this buffer to go to specific file and line if you want
  to see more context. If you have run `:GHLitePRSelect` initially and PR
  branch is not checked out plugin will ask if you want to checkout branch.
  Comments as diagnostics will be show in opened files as well.

- Run `:GHLitePRLoadComments` to review all comments in the code if diff view
  is not enough. List of comments is loaded to quickfix and shown in file as
  diagnostic messages.

- Run `:GHLitePRAddComment` to comment in existing conversations or start the
  new one. Alternatively you can use `:GHLitePROpenComment` to open comments in
  browser.

- Run `:GHLitePRApprove` to approve PR if everything is OK. you can use
  `Ctrl-a` in diff and pr views.

## Commands

### GHLitePRSelect

This command shows selection of active PRs and selects PR for other operations.
You can use this command if you want to review PR without checking it out.

### GHLitePRCheckout

This command shows selection of active PRs and checkouts selected PR.

### GHLitePRView

This command shows PR information (wrapper for `gh pr view`).

Supported key bindings:

* `Ctrl-a` to approve PR

* `Ctrl-m` to merge PR (see `GHLitePRMerge` for details)

Note: You can use default vim shortcuts as well, like `gx` to open links in
this view.

### GHLitePRApprove

This command approves selected PR.

### GHLitePRMerge

This command merges selected PR. Approved and non-approved PRs use different
options when running `gh pr merge` command. Check `gh pr merge -h` for
available options and use them in config's `merge` section if defaults are not
working for you.

### GHLitePRAddPRComment

This command allows to comment on PR at top level (vs commenting on the code).

### GHLitePRLoadComments

This command loads PR comments. Only non-outdated review comments are loaded,
PR comments are not loaded. Comments are loaded to quickfix list and to buffer
diagnostics on buffer load. Navigate quickfix list using `cnext` and `cprev`
(assumption here that you are using quickfix list in general).

NOTE: You must checkout git branch related to PR either using
`:GHLitePRCheckout` or using other tools.

### GHLitePRDiff

This command loads PR diff that you can review. This command shows diff of
selected PR. If no PR is selected then PR number is resolved from git branch
associated with PR. Comments are loaded and shown as diagnostics in this view
as well.

Supported key bindings:

* `gf` go to file from PR diff. `gf` command will not work if you use
  `:GHLitePRSelect` command and branch is not checked out or you have different
  branch checked out.

* `Ctrl-a` to approve PR

### GHLitePRDiffview

This command shows PR diff using
[Diffview.nvim](https://github.com/sindrets/diffview.nvim).

However note that this command shows diff between what's in main branch and PR
branch. This might be different from what's shown in GitHub. E.g. if there are
changes in your main branch and your branch does not have changes from main
branch, then you will be shown that some things are missing in your branch.

### GHLitePRAddComment

This command opens buffer where you can write your comment.

If you want to create multi-line comment then select multiple lines using
visual mode.

Supported key bindings:

* ctrl-enter:

    * If there is already loaded comment on cursor line (using
      `GHLitePRLoadComments` command) then comment is added as reply to thread.

    * If there is no comment on line then new conversation is started.

### GHLitePRUpdateComment

This command updates selected comment.

### GHLitePRDeleteComment

This command deletes selected comment.

### GHLitePROpenComment

Opens comment under cursor in browser using `open_command` command (default
`open`).
