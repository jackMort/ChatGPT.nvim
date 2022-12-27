local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")
local Session = require("chatgpt.flows.chat.session")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

local function write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

M.get_panel = function(type)
  M.panel = Popup(Config.options.sessions_window)

  local sessions = Session.list_sessions()
  -- write details as virtual text
  local details = {}
  for i, session in pairs(sessions) do
    local icon = i == 1 and "  " or "  "
    local cls = i == 1 and "ErrorMsg" or "Comment"
    local vt = {
      { icon .. session.name, cls },
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
    M.vts[line - 1] = write_virtual_text(M.panel.bufnr, namespace_id, line - 1, d)
    line = line + 1
  end

  return M.panel
end

return M
