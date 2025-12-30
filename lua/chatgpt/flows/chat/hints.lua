local Popup = require("nui.popup")
local Config = require("chatgpt.config")

local M = {}

-- Hint definitions per context
-- Format: { key = "keybinding", label = "action" }
local hint_definitions = {
  chat_window = {
    { key = "]m/[m", label = "nav" },
    { key = "]c/[c", label = "code" },
    { key = "y", label = "copy" },
    { key = "d", label = "del" },
    { key = "za", label = "fold" },
    { key = "gs", label = "settings" },
    { key = "gh", label = "help" },
  },
  chat_input = {
    { key = "⏎", label = "send" },
    { key = "@", label = "context" },
    { key = "Tab", label = "switch" },
    { key = "↑/↓", label = "history" },
    { key = "gh", label = "help" },
  },
  chat_input_streaming = {
    { key = "C-c", label = "stop" },
    { key = "Tab", label = "switch" },
    { key = "gh", label = "help" },
  },
  sessions_panel = {
    { key = "⏎", label = "open" },
    { key = "r", label = "rename" },
    { key = "d", label = "delete" },
    { key = "gp", label = "close" },
    { key = "gh", label = "help" },
  },
  settings_panel = {
    { key = "Tab", label = "switch" },
    { key = "gs", label = "close" },
    { key = "gh", label = "help" },
  },
  help_panel = {
    { key = "Tab", label = "switch" },
    { key = "gh", label = "close" },
  },
  system_role_panel = {
    { key = "Tab", label = "switch" },
    { key = "gr", label = "close" },
    { key = "gh", label = "help" },
  },
  default = {
    { key = "Tab", label = "switch" },
    { key = "q", label = "close" },
    { key = "gh", label = "help" },
  },
}

M.panel = nil
M.current_context = "default"

function M.get_panel()
  if M.panel then
    return M.panel
  end

  M.panel = Popup({
    focusable = false,
    border = {
      style = "none",
    },
    win_options = {
      winhighlight = "Normal:ChatGPTHintsBar,FloatBorder:ChatGPTHintsBar",
    },
    buf_options = {
      buftype = "nofile",
      swapfile = false,
    },
  })

  return M.panel
end

function M.render(context)
  if not M.panel or not M.panel.bufnr then
    return
  end

  M.current_context = context or M.current_context
  local hints = hint_definitions[M.current_context] or hint_definitions.default

  -- Build hint string to calculate width for centering
  local hint_str = ""
  for i, h in ipairs(hints) do
    hint_str = hint_str .. h.key .. " " .. h.label
    if i < #hints then
      hint_str = hint_str .. " • "
    end
  end

  -- Calculate padding for centering
  local win_width = M.panel.winid and vim.api.nvim_win_get_width(M.panel.winid) or 80
  local hint_len = vim.fn.strdisplaywidth(hint_str)
  local padding = math.max(0, math.floor((win_width - hint_len) / 2))

  -- Build virtual text: "key label • key label • ..."
  local virt_text = {}
  if padding > 0 then
    table.insert(virt_text, { string.rep(" ", padding), "ChatGPTHintsBar" })
  end
  for i, h in ipairs(hints) do
    table.insert(virt_text, { h.key, "ChatGPTHintsKey" })
    table.insert(virt_text, { " " .. h.label, "ChatGPTHintsText" })
    if i < #hints then
      table.insert(virt_text, { " • ", "ChatGPTHintsSep" })
    end
  end

  -- Clear buffer content
  vim.api.nvim_buf_set_lines(M.panel.bufnr, 0, -1, false, { "" })

  -- Add virtual text
  vim.api.nvim_buf_set_extmark(M.panel.bufnr, Config.namespace_id, 0, 0, {
    virt_text = virt_text,
    virt_text_pos = "overlay",
  })
end

function M.update(context)
  M.render(context)
end

return M
