require('ghlite.types')

local M = {}

--- @type PullRequest|nil
M.selected_PR = nil

--- @type table<string, GroupedComment[]>
M.comments_list = {}

--- @type number|nil PR whose comments `comments_list` holds
M.comments_pr_number = nil

--- @type table<number, PendingReview> keyed by PR number
M.pending_reviews = {}

--- @type table<number, true> PRs whose pending review was already looked up on GitHub
M.pending_reviews_checked = {}

--- @type 'github'|'agent'|nil review that new comments join when both are open: the one started last
M.review_target = nil

--- @type integer|nil Diff view buffer id
M.diff_buffer_id = nil

--- @type boolean whether the diff view shows local changes rather than a PR
M.diff_is_local = false

--- @type table<string, table<number, number>>
M.filename_line_to_diff_line = {}

--- @type table<number, FileNameAndLinePair>
M.diff_line_to_filename_line = {}

return M
