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

--- @type integer|nil Diff view buffer id
M.diff_buffer_id = nil

--- @type table<string, table<number, number>>
M.filename_line_to_diff_line = {}

--- @type table<number, FileNameAndLinePair>
M.diff_line_to_filename_line = {}

return M
