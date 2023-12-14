local M = {}
M.vts = {}

local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Popup = require("nui.popup")
local Config = require("chatgpt.config")

M.get_help_panel = function(type)
  M.type = type
  M.panel = Popup(Config.options.help_window)

  local line = 1

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

  -- find the longest setting value
  local max_setting_value_length = 0
  for _, k in pairs(settings_keys) do
    if #settings[k] > max_setting_value_length then
      max_setting_value_length = #settings[k]
    end
  end

  for _, k in pairs(settings_keys) do
    local key = NuiText(
      " " .. settings[k] .. string.rep(" ", max_setting_value_length + 1 - #settings[k]),
      Config.options.highlights.help_key
    )

    -- make desciption human readable by replacing _ with space
    local description = k:gsub("_", " ")

    local value = NuiText(description, Config.options.highlights.help_description)
    local line_text = NuiLine({ key, value })

    line_text:render(M.panel.bufnr, -1, line)
    line = line + 1
  end

  return M.panel
end

return M
