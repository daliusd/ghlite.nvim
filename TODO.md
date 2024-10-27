# TODO

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
- [x] Support comments in diff view
- [x] Maybe we should add more key bindings to diff, like `gt` or `gs`
- [x] Fix messages with key bindings with override keys
- [x] use html_url of last comment in conversation
- [x] Keep old comments information in group (addition, update and deletion will be smoother)
- [x] Rethink how to simplify which PR to use as we have selected and checked
  out PRs and that's confusing. As well selected PR might not match checked out
  PR. As well we might get assumed selected PR if we have PR branch checked
  out.
- [x] Improve commenting in diff view
- [x] Delete comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Update comment (select from existing ones if more than one, test fresh comment scenario)
- [ ] Allow to comment on multiple lines (visual mode)
- [ ] Support [diffview.nvim](https://github.com/sindrets/diffview.nvim)
