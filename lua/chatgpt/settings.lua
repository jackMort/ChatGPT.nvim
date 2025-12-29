local M = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")
local Context = require("chatgpt.context")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

local params_to_show = { "model" }

local function write_virtual_text(bufnr, ns, line, chunks)
  return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
end

-- Track context item line mappings for deletion
M.context_line_map = {}

M.get_settings_panel = function(type, params, session_name)
  local settings_window_opts = vim.tbl_deep_extend("force", {}, Config.options.settings_window, {
    border = {
      text = {
        top = " Settings (read-only) ",
      },
    },
  })
  M.panel = Popup(settings_window_opts)

  -- Render after mount to get window dimensions
  M.panel:on("BufWinEnter", function()
    M.render_content(params, session_name)
  end)

  -- Set up delete keymap for context items
  M.panel:map("n", Config.options.chat.keymaps.delete_context_item, function()
    local cursor_line = vim.api.nvim_win_get_cursor(M.panel.winid)[1]
    local context_index = M.context_line_map[cursor_line]
    if context_index then
      Context.remove(context_index)
      M.render_content(params, session_name)
      vim.notify("Context item removed")
    end
  end, { noremap = true, silent = true })

  return M.panel
end

M.render_content = function(params, session_name)
  if not M.panel or not M.panel.winid or not vim.api.nvim_win_is_valid(M.panel.winid) then
    return
  end

  local win_height = vim.api.nvim_win_get_height(M.panel.winid)
  local total_lines = win_height

  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(M.panel.bufnr, namespace_id, 0, -1)
  M.context_line_map = {}

  -- Create empty lines for the full window height
  local lines = {}
  for _ = 1, total_lines do
    table.insert(lines, "")
  end

  -- Temporarily make buffer modifiable
  vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.panel.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.panel.bufnr, "modifiable", false)

  local content = {}

  -- Add params
  for _, key in ipairs(params_to_show) do
    if params[key] ~= nil then
      table.insert(content, {
        { Config.options.settings_window.setting_sign .. key .. ": ", "Comment" },
        { tostring(params[key]), Config.options.highlights.params_value },
      })
    end
  end

  -- Add session name if provided
  if session_name then
    table.insert(content, {
      { Config.options.settings_window.setting_sign .. "session: ", "Comment" },
      { session_name, Config.options.highlights.params_value },
    })
  end

  -- Add context items if any
  local context_items = Context.get_items()
  if #context_items > 0 then
    -- Add separator before context
    table.insert(content, {
      { "  ───────────────────────────────", "Comment" },
    })
    -- Add context header
    table.insert(content, {
      { "  context:", "Comment" },
    })
    -- Add each context item
    for idx, item in ipairs(context_items) do
      local display_text
      if item.type == "lsp" then
        display_text = string.format("@%s:%d", item.file or item.name, item.line or 0)
      elseif item.type == "project" then
        display_text = "@" .. item.name
      else
        display_text = "@" .. (item.name or "unknown")
      end
      table.insert(content, {
        { "    " .. display_text, "String" },
      })
      -- Track which line this context item is on (1-indexed for cursor)
      M.context_line_map[#content] = idx
    end
  end

  -- Write content at top
  for i, detail in ipairs(content) do
    write_virtual_text(M.panel.bufnr, namespace_id, i - 1, detail)
  end

  -- Write helper text at bottom
  local separator_line = total_lines - 2
  local help_line = total_lines - 1

  write_virtual_text(M.panel.bufnr, namespace_id, separator_line, {
    { "  ───────────────────────────────", "Comment" },
  })
  write_virtual_text(M.panel.bufnr, namespace_id, help_line, {
    { "  Configure in ", "Comment" },
    { "require('chatgpt').setup()", "String" },
  })
end

return M
