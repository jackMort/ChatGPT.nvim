local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")
local Session = require("chatgpt.flows.chat.session")
local Utils = require("chatgpt.utils")
local InputWidget = require("chatgpt.common.input_widget")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

M.set_current_line = function()
  M.current_line, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))
  M.render_list()
end

M.set_session = function()
  M.active_line = M.current_line
  local selected = M.sessions[M.current_line]
  local session = Session.new({ filename = selected.filename })
  M.render_list()
  M.set_session_cb(session)
end

M.rename_session = function()
  M.active_line = M.current_line
  local selected = M.sessions[M.current_line]
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
  local selected = M.sessions[M.current_line]
  if M.active_line ~= M.current_line then
    local session = Session.new({ filename = selected.filename })
    session:delete()
    M.sessions = Session.list_sessions()
    if M.active_line > M.current_line then
      M.active_line = M.active_line - 1
    end
    M.render_list()
  else
    vim.notify("Cannot remove active session", vim.log.levels.ERROR)
  end
end

M.render_list = function()
  vim.api.nvim_buf_clear_namespace(M.panel.bufnr, namespace_id, 0, -1)

  local details = {}
  for i, session in pairs(M.sessions) do
    local icon = i == M.active_line and Config.options.chat.sessions_window.active_sign
      or Config.options.chat.sessions_window.inactive_sign
    local cls = i == M.active_line and Config.options.highlights.active_session or "Comment"
    local name = Utils.trimText(session.name, 30)
    local vt = {
      { (M.current_line == i and Config.options.chat.sessions_window.current_line_sign or " ") .. icon .. name, cls },
    }
    table.insert(details, vt)
  end

  local line = 1
  local empty_lines = {}
  for _ = 1, #details do
    table.insert(empty_lines, "")
  end

  vim.api.nvim_buf_set_lines(M.panel.bufnr, line - 1, line - 1 + #empty_lines, false, empty_lines)
  for _, d in ipairs(details) do
    M.vts[line - 1] = vim.api.nvim_buf_set_extmark(
      M.panel.bufnr,
      namespace_id,
      line - 1,
      0,
      { virt_text = d, virt_text_pos = "overlay" }
    )
    line = line + 1
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
