local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")

M.get_help_panel = function(filetype)
  M.filetype = filetype
  M.panel = Popup(Config.options.help_window)

  local line = 0

  local settings = Config.options.edit_with_instructions.keymaps
  for _, v in pairs(settings) do
    local line_text = _ .. ": '" .. v .. "'"
    vim.api.nvim_buf_set_lines(M.panel.bufnr, line, line + 1, false, { line_text })
    line = line + 1
  end

  vim.api.nvim_buf_set_option(M.panel.bufnr, "filetype", filetype)
  return M.panel
end

return M
