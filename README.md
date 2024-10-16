# ghlite.nvim

Neovim plugin to work GitHub PRs quickly.

Main idea of this plugin to have tools that augment GitHub PR review using web
instead of replacing it like other plugins do.

## Requirements

- nvim 0.10+

- [GitHub CLI (gh)](https://cli.github.com/)

- If you are using fzf-lua or telescope you might want to checkout how to
  override UI select. E.g. `vim.cmd('FzfLua register_ui_select')`

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
        keymaps = { -- override default keymaps with the ones you prefer
          diff = {
            open_file = 'gf',
            approve = '<C-A>',
          },
          comment = {
            send_comment = '<C-CR>'
          },
          pr = {
            approve = '<C-A>',
          },
        },
      })
    end,
    keys = {
      { '<leader>us', ':GHLitePRSelect<cr>',       silent = true },
      { '<leader>uo', ':GHLitePRCheckout<cr>',     silent = true },
      { '<leader>uv', ':GHLitePRView<cr>',         silent = true },
      { '<leader>uu', ':GHLitePRLoadComments<cr>', silent = true },
      { '<leader>up', ':GHLitePRDiff<cr>',         silent = true },
      { '<leader>ua', ':GHLitePRAddComment<cr>',   silent = true },
      { '<leader>ug', ':GHLitePROpenComment<cr>',  silent = true },
    }
  }
```

## PR Review using ghlite.nvim

- Run `:GHLitePRSelect` or `:GHLitePRCheckout` and select PR you want to
  review. PR view will open. You can open `:GHLitePRView` anytime later to
  refresh/reopen PR view. You can skip this step if you have locally branch
  checked out that is related to PR. In that case plugin will resolve PR
  number.

- Run `:GHLitePRDiff` to see diff of PR so you could review it in single
  window. Use `gf` in this buffer to go to specific file and line if you want
  to see more context.

- Run `:GHLitePRLoadComments` to review comment in the code. List of comments
  is loaded to quickfix and shown in file as diagnostic messages.

- Run `:GHLitePRAddComment` to comment in existing conversations or start the
  new one. Alternatively you can use `:GHLitePROpenComment` to open comments in
  browser.

- Run `:GHLitePRApprove` to approve PR if everything is OK. Most probably you
  will use `Ctrl-a` in diff or pr views.

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

Note: You can use default vim shortcuts as well, like `gx` to open links in
this view.

### GHLitePRApprove

This command approves active PR.

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
associated with PR.

Supported key bindings:

* `gf` go to file from PR diff. `gf` command will not work if you use
  `:GHLitePRSelect` command and branch is not checked out or you have different
  branch checked out.

* `Ctrl-a` to approve PR

### GHLitePRAddComment

This command opens buffer where you can write your comment.

Supported key bindings:

* ctrl-enter:

    * If there is already loaded comment on cursor line (using
      `GHLitePRLoadComments` command) then comment is added as reply to thread.

    * If there is no comment on line then new conversation is started.

### GHLitePROpenComment

Opens comment under cursor in browser using `open_command` command (default
`open`).

## TODO

- [x] Investigate if I can use quickfix list and show comments on hover
- [x] Show virtual text or diagnostics for comments
- [x] Keep file paths relative to git root
- [x] Show diff hunk with comments
- [x] Show PR diff
- [x] Go to file from PR diff
- [x] Allow to reply in existing threads
- [x] Allow to comment directly in the code
- [x] Handle error on reply/comment
- [x] Update quickfix list on reply/comment
- [x] ~~Use plenary Jobs~~ use vim.system
- [x] Sort comments by filename and line number
- [x] ~~Use temp files instead of nofile for comment and diff window~~ There is no value in this.
- [x] Select comment on reply if there are multiple comments on the same line
- [x] nil PR
- [x] Open comment thread in browser
- [x] Checkout PR
- [x] Allow to configure how diff and comment windows are shown (split, vsplit or in the same window)
- [x] Add open command in config
- [x] Update README
- [x] Fix `gf` command when cwd is not at the git root
- [x] Go to exact line from diff (resolve line from diff)
- [x] Allow to select PR without checking it out: quite some functionality
  should work without checking out
- [ ] Support comments in diff view
- [ ] Keep old comments information in group (addition, update and deletion will be smoother)
- [ ] Update comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Delete comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Allow to comment on multiple lines (visual mode)
- [ ] Maybe we should add more key bindings to diff, like `gt` or `gs`
- [ ] use html_url of last comment in conversation
- [ ] Support [diffview.nvim](https://github.com/sindrets/diffview.nvim)
- [ ] Fix messages with key bindings with override keys
