-- ChatAction that can be used for actions of type "chat" in actions.json
--
-- This enables the use of gpt-3.5-turbo in user defined actions,
-- as this model only defines the chat endpoint and has no completions endpoint
--
-- Example action for your local actions.json:
--
--   "turbo-summary": {
--     "type": "chat",
--     "opts": {
--       "template": "Summarize the following text.\n\nText:\n\"\"\"\n{{input}}\n\"\"\"\n\nSummary:",
--       "params": {
--         "model": "gpt-3.5-turbo"
--       }
--     }
--   }
local classes = require("chatgpt.common.classes")
local BaseAction = require("chatgpt.flows.actions.base")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

local ChatAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_APPEND = "append"
local STRATEGY_PREPEND = "prepend"
local STRATEGY_DISPLAY = "display"
local STRATEGY_DIFF = "diff"

function ChatAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_APPEND
end

function ChatAction:render_template()
  local data = {
    filetype = self:get_filetype(),
    input = self:get_selected_text(),
  }
  data = vim.tbl_extend("force", {}, data, self.variables)
  local result = self.template
  for key, value in pairs(data) do
    result = result:gsub("{{" .. key .. "}}", value)
  end
  return result
end

function ChatAction:get_params()
  local additional_params = {}
  local p_rendered = self:render_template()
  local p1, s1 = string.match(p_rendered, "(.*)%[insert%](.*)")
  if s1 ~= nil then
    additional_params["suffix"] = s1
    p_rendered = p1
  end
  local messages = {}
  local message = {}
  message.role = "user"
  message.content = p_rendered
  table.insert(messages, message)
  additional_params["messages"] = messages
  return vim.tbl_extend("force", Config.options.openai_params, self.params, additional_params)
end

function ChatAction:run()
  vim.schedule(function()
    self:set_loading(true)

    local params = self:get_params()
    Api.chat_completions(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end)
end

function ChatAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)

    local bufnr = self:get_bufnr()
    if self.strategy == STRATEGY_PREPEND then
      answer = answer .. "\n" .. self:get_selected_text()
    elseif self.strategy == STRATEGY_APPEND then
      answer = self:get_selected_text() .. "\n\n" .. answer .. "\n"
    end
    local lines = Utils.split_string_by_line(answer)
    local start_row, start_col, end_row, end_col = self:get_visual_selection()

    if self.strategy == STRATEGY_APPEND then
      local Popup = require("nui.popup")

      local popup = Popup({
        position = 1,
        size = {
          width = 60,
          height = 10,
        },
        relative = {
          type = "buf",
          position = {
            row = start_row,
            col = start_col,
          },
        },
        padding = { 1, 1, 1, 1 },
        enter = true,
        focusable = true,
        zindex = 50,
        border = {
          style = "single",
        },
        buf_options = {
          modifiable = false,
          readonly = true,
        },
        win_options = {
          winblend = 20,
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
      })
      vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, lines)
      popup:mount()
    elseif self.strategy == STRATEGY_DIFF then
      -- create a new buffer for the answer
      local newbufnr = vim.api.nvim_create_buf(false, true)
      -- set filetype to the same as the original buffer
      vim.api.nvim_buf_set_option(newbufnr, "filetype", self:get_filetype())
      -- give a name to the new buffer
      vim.api.nvim_buf_set_name(newbufnr, "ChatGPT answer " .. vim.api.nvim_buf_get_name(bufnr))
      -- copy the old buffer into the new buffer
      vim.api.nvim_buf_set_lines(newbufnr, 0, -1, false, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      -- replace the answer in the new buffer
      vim.api.nvim_buf_set_text(newbufnr, start_row, start_col, end_row, end_col, lines)
      -- create a new tab with the new buffer and the old buffer side by side, then diff
      -- them
      vim.api.nvim_command("tabnew | buffer " .. bufnr .. "| vsplit | buffer " .. newbufnr .. " | windo diffthis")
      -- set a tab-scoped variable to handle special commands
      vim.t.chatgpt_diff = { newbufnr, bufnr }
      -- map q to close the tab if t:chatgpt_diff is set
      vim.api.nvim_buf_set_keymap(
        0,
        "n",
        "q",
        "<cmd>lua if vim.t.chatgpt_diff ~= nil then require'chatgpt.utils'.keep_or_restore("
          .. bufnr
          .. ","
          .. newbufnr
          .. ") end <CR>",
        { noremap = true, silent = true }
      )
    else
      vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)

      -- set the cursor onto the answer
      if self.strategy == STRATEGY_APPEND then
        local target_line = end_row + 3
        vim.api.nvim_win_set_cursor(0, { target_line, 0 })
      end
    end
  end)
end

return ChatAction
