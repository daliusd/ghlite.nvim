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

Using lazyvim

```lua
  {
    'daliusd/ghlite.nvim',
    config = function()
      require('ghlite').setup({
        debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
        diff_split = 'vsplit', -- set to empty string '' to open in active buffer
        comment_split = 'split', -- set to empty string '' to open in active buffer
        open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
      })
    end,
    keys = {
      { '<leader>uo', ':GHLitePRCheckout<cr>',     silent = true },
      { '<leader>uu', ':GHLitePRLoadComments<cr>', silent = true },
      { '<leader>up', ':GHLitePRDiff<cr>',         silent = true },
      { '<leader>ua', ':GHLitePRAddComment<cr>',   silent = true },
      { '<leader>ug', ':GHLitePROpenComment<cr>',  silent = true },
    }
  }
```

## Commands

### GHLitePRCheckout

This command shows selection of active PRs and checkouts selected PR.

### GHLitePRLoadComments

This command loads PR comments. Only non-outdated review comments are loaded,
PR comments are not loaded. Comments are loaded to quickfix list and to buffer
diagnostics on buffer load. Navigate quickfix list using `cnext` and `cprev`
(assumption here that you are using quickfix list in general).

### GHLitePRDiff

This command loads PR diff that you can review.

Supported key bindings:

* `gf` go to file from PR diff.

* `ESC` or `q` closes PR diff buffer.

### GHLitePRAddComment

This command opens buffer where you can write your comment.

Supported key bindings:

* ctrl-enter:

    * If there is already loaded comment on cursor line (using
      `GHLitePRLoadComments` command) then comment is added as reply to thread.

    * If there is no comment on line then new conversation is started.

* `ESC` or `q` closes comment buffer.

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
- [ ] Keep old comments information in group (addition, update and deletion will be smoother)
- [ ] Update comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Delete comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Allow to comment on multiple lines (visual mode)
- [ ] Go to exact line from diff (resolve line from diff)
- [ ] Maybe we should add more key bindings to diff, like `gt` or `gs`
- [ ] use html_url of last comment in conversation
