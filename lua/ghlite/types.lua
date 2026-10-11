--- @class Comment
--- @field id number
--- @field url string
--- @field path string
--- @field line number
--- @field start_line number
--- @field original_line? number
--- @field original_start_line? number
--- @field outdated boolean
--- @field user string
--- @field body string
--- @field updated_at string
--- @field diff_hunk string
--- @field commit_id? string
--- @field original_commit_id? string
--- @field pending boolean held in an unsubmitted review

--- @class GroupedComment
--- @field id number
--- @field line number
--- @field start_line number
--- @field outdated boolean
--- @field url string
--- @field content string
--- @field comments Comment[]
--- @field commit_id? string
--- @field original_commit_id? string
--- @field thread_id? string
--- @field resolved boolean

--- A review that exists on GitHub but has not been submitted yet. Comments added
--- while it is open stay invisible to everyone else until the review is submitted.
--- @class PendingReview
--- @field id number REST review id, used to submit and discard
--- @field node_id string GraphQL review id, used to attach comments
--- @field pr_number number PR the review belongs to

--- A comment held in an agent review session until it is exported.
--- @class AgentDraft
--- @field id number
--- @field path string relative to the git root
--- @field start_line number
--- @field line number
--- @field body string
--- @field created_at string

--- @class AgentSession
--- @field root string git root the session belongs to
--- @field next_id number
--- @field drafts AgentDraft[]

--- Local changes an agent review covers when no PR is selected.
--- @class LocalScope
--- @field base string ref the changes are compared against, e.g. origin/HEAD
--- @field merge_base string commit sha

--- @class FileNameAndLinePair
--- @field [1] string filename
--- @field [2] number line

--- @class ChangedFile
--- @field filename string
--- @field status string

--- @class Commit
--- @field oid string
--- @field messageHeadline string
--- @field messageBody string
--- @field authoredDate string
--- @field committedDate string
--- @field authors { login?: string, name?: string, email?: string }[]

--- @class CommitFile
--- @field filename string
--- @field previous_filename? string
--- @field status string
--- @field additions number
--- @field deletions number
--- @field patch? string

--- @class CommitDetails
--- @field sha string
--- @field html_url string
--- @field commit { message: string, author: table, committer: table, verification?: table }
--- @field author? { login: string }
--- @field committer? { login: string }
--- @field parents { sha: string }[]
--- @field stats { additions: number, deletions: number, total: number }
--- @field files CommitFile[]

--- @class PullRequest
--- @field number number
--- @field title? string
--- @field author? { login: string }
--- @field labels? { name: string }[]
--- @field createdAt? string
--- @field isDraft? boolean
--- @field updatedAt? string
--- @field baseRefName string
--- @field baseRefOid string
--- @field headRefName string
--- @field headRefOid string
--- @field reviewDecision string
--- @field statusCheckRollup? StatusCheckRollup[]

--- @class StatusCheckRollup
--- @field __typename? 'CheckRun'|'StatusContext'
--- @field name? string CheckRun name
--- @field context? string legacy commit-status context name
--- @field status? string CheckRun status, e.g. queued, in_progress, completed
--- @field conclusion? string CheckRun conclusion when completed
--- @field state? string legacy commit-status state, e.g. SUCCESS, FAILURE, PENDING
--- @field workflowName? string
--- @field description? string
--- @field detailsUrl? string
--- @field targetUrl? string

--- @class ExportComment
--- @field author string
--- @field body string
--- @field pending boolean

--- @class ExportThread
--- @field path string relative to the git root
--- @field line number
--- @field start_line? number
--- @field outdated boolean
--- @field resolved boolean
--- @field url? string
--- @field diff_hunk? string
--- @field comments ExportComment[]

--- A PR-level review summary or conversation comment.
--- @class ExportNote
--- @field author string
--- @field state? string review state, e.g. CHANGES_REQUESTED
--- @field body string

--- @class ExportPullRequest
--- @field number number
--- @field title? string
--- @field url? string
--- @field head? string head commit sha

--- Everything one export renders; also handed to a custom `agent.output` function.
--- @class ExportData
--- @field pr? ExportPullRequest
--- @field scope? LocalScope set instead of `pr` when local changes were reviewed
--- @field summary? string
--- @field drafts AgentDraft[]
--- @field reviews ExportNote[]
--- @field pr_comments ExportNote[]
--- @field threads ExportThread[]
