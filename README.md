# ghlite.nvim

Neovim plugin to work GitHub PRs quickly.

Main idea of this plugin to have tools that augment GitHub PR review using web
instead of replacing it like other plugins do.

[![ghlite.nvim intro](https://img.youtube.com/vi/TwzA3bhLrE4/0.jpg)](https://www.youtube.com/watch?v=TwzA3bhLrE4)

## Requirements

- nvim 0.10+

- [GitHub CLI (gh)](https://cli.github.com/)

- [async.nvim](https://github.com/lewis6991/async.nvim)

- If you are using fzf-lua or telescope you might want to checkout how to
  override UI select. E.g. `vim.cmd('FzfLua register_ui_select')`

- [Diffview.nvim](https://github.com/sindrets/diffview.nvim) (optional, for enhanced diff viewing)

- [codediff.nvim](https://github.com/esmuellert/codediff.nvim) (optional, alternative for enhanced diff viewing)

## Installation

Using lazyvim.

NOTE: default config here. You can skip all the settings if you are OK with defaults.

```lua
  {
    'daliusd/ghlite.nvim',
    dependencies = { 'lewis6991/async.nvim' },
    config = function()
      require('ghlite').setup({
        debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
        view_split = 'vsplit', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
        diff_split = 'vsplit', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
        diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto' - which tool to use for GHLitePRDiffview
        comment_split = 'split', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
        comment_hunk = true, -- show GitHub diff hunks in loaded PR comment diagnostics and quickfix entries
        open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
        merge = {
          approved = '--squash',
          nonapproved = '--auto --squash',
        },
        html_comments_command = { 'lynx', '-stdin', '-dump' }, -- command to render HTML comments in PR view
        -- custom shell commands runnable from the PR view, output opens in a new buffer
        pr_commands = {
          {
            name = 'AI Review', -- shown in the PR view keymap hints
            cmd = 'pi -p "review this PR"', -- run in the repository root
            key = 'cr', -- set to '' to disable the keymap
          },
        },
        -- override default keymaps with the ones you prefer
        -- set keymap to false or '' to disable it
        keymaps = {
          diff = {
            open_file = 'gf',
            open_file_tab = '',
            open_file_split = 'o',
            open_file_vsplit = 'O',
            approve = 'cA',
            request_changes = 'cR',
          },
          comment = {
            send_comment = 'c<CR>' -- this one cannot be disabled
          },
          pr = {
            approve = 'cA',
            request_changes = 'cR',
            merge = 'cM',
            comment = 'ca',
            diff = 'cp',
            checkout = 'co',
            refresh = 'r',
            open_commit = 'cs', -- open commit view for the commit under the cursor (<CR> works too)
          },
          commit = {
            open_file = 'gf',
            open_file_split = 'o',
            open_file_vsplit = 'O',
            diff = 'cp',
            next_commit = ']c',
            prev_commit = '[c',
            yank_sha = 'y',
            open_in_browser = 'gx',
            refresh = 'r',
            close = 'q',
          },
        },
      })
    end,
    keys = {
      -- { '<leader>us', ':GHLitePRList<cr>',       silent = true, desc = 'PR List' },
      { '<leader>us', ':GHLitePRSelect<cr>',        silent = true, desc = 'PR Select' },
      { '<leader>uo', ':GHLitePRCheckout<cr>',      silent = true, desc = 'PR Checkout' },
      { '<leader>uv', ':GHLitePRView<cr>',          silent = true, desc = 'PR View' },
      { '<leader>uu', ':GHLitePRLoadComments<cr>',  silent = true, desc = 'PR Load Comments' },
      { '<leader>up', ':GHLitePRDiff<cr>',          silent = true, desc = 'PR Diff' },
      { '<leader>ul', ':GHLitePRDiffview<cr>',      silent = true, desc = 'PR Diffview' },
      { '<leader>ua', ':GHLitePRAddComment<cr>',    silent = true, desc = 'PR Add comment' },
      { '<leader>ua', ':GHLitePRAddComment<cr>',    mode = 'x',    silent = true,             desc = 'PR Add comment' },
      { '<leader>uc', ':GHLitePRUpdateComment<cr>', silent = true, desc = 'PR Update comment' },
      { '<leader>ud', ':GHLitePRDeleteComment<cr>', silent = true, desc = 'PR Delete comment' },
      { '<leader>ug', ':GHLitePROpenComment<cr>',   silent = true, desc = 'PR Open comment' },
    }
  }
```

## Development

Run the test suite with:

```bash
make test
```

The test target bootstraps [mini.nvim](https://github.com/echasnovski/mini.nvim) into `.tests/` and runs `mini.test` in headless Neovim.

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
  `ca` in diff and pr views.

- Run `:GHLitePRRequestChanges` to request changes on PR if something is wrong.
  you can use `cr` in diff and pr views.

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
  `ca` in diff and pr views.

- Run `:GHLitePRRequestChanges` to request changes on PR if something is wrong.
  you can use `cr` in diff and pr views.

## Commands

### GHLitePRList

Opens a reusable buffer containing the same pull requests as `GHLitePRSelect`. Each PR is shown across several lines with its number, title, author, creation/update dates, draft/review status, and labels.

Supported key bindings:

- `cs` or `<CR>` opens the PR under the cursor
- `co` checks out and opens the PR under the cursor
- `r` refreshes the list
- `q` closes the list

### GHLitePRSelect

This command shows selection of active PRs and selects PR for other operations.
You can use this command if you want to review PR without checking it out.

### GHLitePRCheckout

This command shows selection of active PRs and checkouts selected PR.

### GHLitePRView

This command shows PR information (wrapper for `gh pr view`).

Supported key bindings:

* `cA` to approve PR

* `cM` to merge PR (see `GHLitePRMerge` for details)

* `ca` to write top level PR comment

* `cp` to open diff view

* `co` to checkout the PR (only shown when the PR isn't already checked out)

* `cs` or `<CR>` to open the commit view for the commit under the cursor (see
  `GHLiteCommitView`)

* `r` to refresh the PR view

* `cr` to run the AI review command (see `pr_commands` below)

The view lists the PR commits under a `## Commits` heading, followed by the
changed files, PR comments and review comments.

#### Custom commands

`pr_commands` lets you run arbitrary shell commands against the PR from the PR
view. Each entry has a `name`, a `cmd` and a `key`, and every configured entry
gets its own key binding and is listed in the PR view key binding hints.

By default a single AI review entry is configured, bound to `cr`:

```lua
pr_commands = {
  { name = 'AI Review', cmd = 'pi -p "review this PR"', key = 'cr' },
}
```

Use it to plug in whatever tool you prefer, for example:

```lua
pr_commands = {
  { name = 'AI Review', cmd = 'claude -p "review this PR"', key = 'cr' },
  { name = 'Tests',     cmd = 'make test',                  key = 'ct' },
}
```

The command is run through the shell (so pipes, quoting and redirects work)
from the repository root, and its output opens in a new read-only buffer using
`view_split`. Because the plugin passes no PR context, the command is expected
to work it out itself, e.g. via `gh pr diff` or `git diff`, which rely on the
PR branch being checked out. For that reason the PR must be checked out before
a command runs: if it isn't, you are asked to check it out first, and the
command is not run if you decline. Set an entry's `key` to `''` to keep the
command configured without binding a key.

Note: You can use default vim shortcuts as well, like `gx` to open links in
this view.

HTML comments is the thing too and they look bad in text. To render HTML as
text `html_comments_command` settings can be used to specify command. You can
use any command here that accepts html via stdin and outputs text to stdout. By
default `lynx` is used, but if something works better for you feel free to use
it.

Plugin searches for html tag and only then passes comment through
`html_comments_command`. You can disable this functionality by setting
`html_comments_command` as `false`.

### GHLitePRApprove

This command approves selected PR.

### GHLitePRRequestChanges

This command request changes on PR.

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

* `cA` to approve PR

### GHLitePRDiffview

This command shows PR diff using either
[Diffview.nvim](https://github.com/sindrets/diffview.nvim) or
[codediff.nvim](https://github.com/esmuellert/codediff.nvim), depending on the
`diff_tool` configuration option:

- `diff_tool = 'auto'` (default): Uses diffview.nvim if installed, otherwise
  codediff.nvim. If both are installed, diffview.nvim is preferred.
- `diff_tool = 'diffview'`: Always uses diffview.nvim (shows error if not
  installed)
- `diff_tool = 'codediff'`: Always uses codediff.nvim (shows error if not
  installed)

This command will not show correct diff sometimes if you have gh older than
2.63.0 (details here https://github.com/cli/cli/pull/9938).

### GHLitePRAddComment

This command opens buffer where you can write your comment.

If you want to create multi-line comment then select multiple lines using
visual mode.

Supported key bindings:

* c-enter:

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

### GHLiteCommitView

Shows a single commit: `:GHLiteCommitView <sha>`. Usually you don't type it -
press `cs` or `<CR>` on a commit in the PR view instead, which also enables
commit-to-commit navigation.

The view shows the SHA, author (and committer, when it differs), parent
commits, the commit message, signature status, CI check runs, the changed files
with their `+`/`-` counts, any review comments left on that commit, and the
commit diff.

Supported key bindings:

* `gf`, `o`, `O` to open the file under the cursor (in the current window, a
  split or a vertical split) at the line the diff points at

* `cp` to open the commit in `diffview.nvim`/`codediff.nvim`

* `]c` and `[c` to move to the next/previous commit of the PR (only when opened
  from the PR view)

* `y` to yank the full SHA

* `gx` to open the commit on GitHub using `open_command`

* `r` to refresh, `q` to close

The commit is fetched from the GitHub API, so it works for PRs that are not
checked out. Opening a file, however, opens the file in your working tree - if
the PR isn't checked out you may land in unrelated code.
