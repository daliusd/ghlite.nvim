--- @class Comment
--- @field id number
--- @field url string
--- @field path string
--- @field line number
--- @field start_line number
--- @field user string
--- @field body string
--- @field updated_at string
--- @field diff_hunk string

--- @class GroupedComment
--- @field id number
--- @field line number
--- @field start_line number
--- @field url string
--- @field content string
--- @field comments Comment[]

--- @class FileNameAndLinePair
--- @field [1] string filename
--- @field [2] number line

--- @class PullRequest
--- @field number number
--- @field baseRefName string
--- @field baseRefOid string
--- @field headRefName string
--- @field headRefOid string
--- @field reviewDecision string
