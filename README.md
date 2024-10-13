# ghlite.nvim

Neovim plugin to work GitHub PRs quickly.

## Requirements

nvim 0.10+

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
- [ ] Allow to configure how diff and comment windows are shown (split, vsplit or in the same window)
- [ ] Add open command in config
- [ ] Update README
- [ ] Keep old comments information in group (addition, update and deletion will be smoother)
- [ ] Update comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Delete comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Allow to comment on multiple lines (visual mode)
