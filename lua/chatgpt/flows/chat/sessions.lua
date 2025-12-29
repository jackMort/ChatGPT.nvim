local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")
local Session = require("chatgpt.flows.chat.session")
local Utils = require("chatgpt.utils")
local InputWidget = require("chatgpt.common.input_widget")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

-- Get date group for a timestamp
local function get_date_group(ts)
  local now = os.time()
  local today_start = os.time({
    year = os.date("%Y"),
    month = os.date("%m"),
    day = os.date("%d"),
    hour = 0,
    min = 0,
    sec = 0,
  })
  local yesterday_start = today_start - 86400
  local week_start = today_start - (86400 * 7)
  local month_start = today_start - (86400 * 30)

  if ts >= today_start then
    return "Today"
  elseif ts >= yesterday_start then
    return "Yesterday"
  elseif ts >= week_start then
    return "This Week"
  elseif ts >= month_start then
    return "This Month"
  else
    return "Older"
  end
end

M.set_current_line = function()
  M.current_line, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))
  M.render_list()
end

-- Get the session index for the current cursor line
M.get_current_session_index = function()
  return M.line_to_session and M.line_to_session[M.current_line] or nil
end

M.set_session = function()
  local session_idx = M.get_current_session_index()
  if not session_idx then
    return -- On a header line
  end
  M.active_line = session_idx
  local selected = M.sessions[session_idx]
  local session = Session.new({ filename = selected.filename })
  M.render_list()
  M.set_session_cb(session)
end

M.rename_session = function()
  local session_idx = M.get_current_session_index()
  if not session_idx then
    return -- On a header line
  end
  local selected = M.sessions[session_idx]
  local session = Session.new({ filename = selected.filename })
  local input_widget = InputWidget("New Name:", function(value)
    if value ~= nil and value ~= "" then
      session:rename(value)
      M.sessions = Session.list_sessions()
      M.render_list()
    end
  end)
  input_widget:mount()
end

M.delete_session = function()
  local session_idx = M.get_current_session_index()
  if not session_idx then
    return -- On a header line
  end
  if M.active_line ~= session_idx then
    local selected = M.sessions[session_idx]
    local session = Session.new({ filename = selected.filename })
    session:delete()
    M.sessions = Session.list_sessions()
    if M.active_line > session_idx then
      M.active_line = M.active_line - 1
    end
    M.render_list()
  else
    vim.notify("Cannot remove active session", vim.log.levels.ERROR)
  end
end

M.render_list = function()
  vim.api.nvim_buf_clear_namespace(M.panel.bufnr, namespace_id, 0, -1)

  -- Group sessions by date
  local groups = {}
  local group_order = { "Today", "Yesterday", "This Week", "This Month", "Older" }
  for _, g in ipairs(group_order) do
    groups[g] = {}
  end

  for i, session in ipairs(M.sessions) do
    local group = get_date_group(session.ts)
    table.insert(groups[group], { index = i, session = session })
  end

  -- Build display list with headers
  local display_lines = {}
  local line_to_session = {} -- Maps display line to session index

  for _, group_name in ipairs(group_order) do
    local group_sessions = groups[group_name]
    if #group_sessions > 0 then
      -- Add header
      table.insert(display_lines, { type = "header", text = group_name })
      -- Add sessions
      for _, entry in ipairs(group_sessions) do
        table.insert(display_lines, { type = "session", index = entry.index, session = entry.session })
        line_to_session[#display_lines] = entry.index
      end
    end
  end

  M.line_to_session = line_to_session

  -- Create buffer lines
  local empty_lines = {}
  for _ = 1, #display_lines do
    table.insert(empty_lines, "")
  end
  vim.api.nvim_buf_set_lines(M.panel.bufnr, 0, -1, false, empty_lines)

  -- Render each line
  for line_num, item in ipairs(display_lines) do
    local line_idx = line_num - 1

    if item.type == "header" then
      -- Render header with separator line
      local header_text = "── " .. item.text .. " " .. string.rep("─", 20)
      vim.api.nvim_buf_set_extmark(M.panel.bufnr, namespace_id, line_idx, 0, {
        virt_text = { { header_text, "ChatGPTSessionHeader" } },
        virt_text_pos = "overlay",
      })
    else
      -- Render session
      local i = item.index
      local session = item.session
      local is_active = (i == M.active_line)
      local is_current = (M.line_to_session[line_num] == M.line_to_session[M.current_line])

      local cursor = is_current and Config.options.chat.sessions_window.current_line_sign or "  "
      local icon = is_active and Config.options.chat.sessions_window.active_sign or Config.options.chat.sessions_window.inactive_sign
      local cls = is_active and Config.options.highlights.active_session or "Comment"
      local name = Utils.trimText(session.name, 28)

      vim.api.nvim_buf_set_extmark(M.panel.bufnr, namespace_id, line_idx, 0, {
        virt_text = { { cursor, "ChatGPTSessionCursor" }, { icon .. name, cls } },
        virt_text_pos = "overlay",
      })
    end
  end
end

M.refresh = function()
  M.sessions = Session.list_sessions()
  M.active_line = 1
  M.current_line = 1
  M.render_list()
end

M.get_panel = function(set_session_cb)
  M.sessions = Session.list_sessions()
  M.active_line = 1
  M.current_line = 1
  M.set_session_cb = set_session_cb

  M.panel = Popup(Config.options.chat.sessions_window)

  M.panel:map("n", Config.options.chat.keymaps.select_session, function()
    M.set_session()
  end, { noremap = true })

  M.panel:map("n", Config.options.chat.keymaps.rename_session, function()
    M.rename_session()
  end, { noremap = true })

  M.panel:map("n", Config.options.chat.keymaps.delete_session, function()
    M.delete_session()
  end, { noremap = true, silent = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = M.panel.bufnr,
    callback = M.set_current_line,
  })

  M.render_list()

  return M.panel
end

return M
