local M = {}

M.selected_PR = nil
M.selected_headRefName = nil
M.comments_list = {}
M.diff_buffer_id = nil
M.filename_line_to_diff_line = {}
M.diff_line_to_filename_line = {}

return M
