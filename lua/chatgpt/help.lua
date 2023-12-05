local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")

M.get_help_panel = function(type)
  M.type = type
  M.panel = Popup(Config.options.help_window)

  local line = 0

  local settings
  if M.type == "edit" then
    settings = Config.options.edit_with_instructions.keymaps
  elseif M.type == "chat" then
    settings = Config.options.chat.keymaps
  else
    settings = {}
  end

  -- sort alphabetically by keys for consistency
  local settings_keys = {}
  -- populate the table that holds the keys
  for k in pairs(settings) do
    table.insert(settings_keys, k)
  end
  -- sort the keys
  table.sort(settings_keys)

  for _, k in pairs(settings_keys) do
    local line_text = k .. ": '" .. settings[k] .. "'"
    vim.api.nvim_buf_set_lines(M.panel.bufnr, line, line + 1, false, { line_text })
    line = line + 1
  end

  vim.api.nvim_buf_set_option(M.panel.bufnr, "filetype", "conf")
  return M.panel
end

return M
