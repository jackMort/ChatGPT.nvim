local classes = require("chatgpt.common.classes")
local BaseAction = require("chatgpt.flows.actions.base")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

-- curl code to insert code between prompt and suffix
-- curl https://api.openai.com/v1/completions \
--   -H "Content-Type: application/json" \
--   -H "Authorization: Bearer $OPENAI_API_KEY" \
--   -d '{
--   "model": "text-davinci-003",
--   "prompt": "Insert a roxygen skeleton to document this R function:\n\n",
--   "suffix": " code ",
--   "temperature": 0.7,
--   "max_tokens": 565,
--   "top_p": 1,
--   "frequency_penalty": 0,
--   "presence_penalty": 0
-- }'

local CompletionAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_APPEND = "append"
local STRATEGY_PREPEND = "prepend"
local STRATEGY_DISPLAY = "display"

function CompletionAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_REPLACE
  self.ui = opts.ui or {}
end

function CompletionAction:render_template()
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

function CompletionAction:get_params()
  local additional_params = {}
  local p_rendered = self:render_template()
  local p1, s1 = string.match(p_rendered, "(.*)%[insert%](.*)")
  if s1 ~= nil then
    additional_params["suffix"] = s1
    p_rendered = p1
  end
  additional_params["prompt"] = p_rendered
  return vim.tbl_extend("force", Config.options.openai_params, self.params, additional_params)
end

function CompletionAction:run()
  vim.schedule(function()
    self:set_loading(true)

    local params = self:get_params()
    Api.completions(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end)
end

function CompletionAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)

    local bufnr = self:get_bufnr()
    if self.strategy == STRATEGY_PREPEND then
      answer = answer .. "\n" .. self:get_selected_text()
    elseif self.strategy == STRATEGY_APPEND then
      answer = self:get_selected_text() .. "\n" .. answer
    end
    local lines = Utils.split_string_by_line(answer)
    local _, start_row, start_col, end_row, end_col = self:get_visual_selection()

    if self.strategy ~= STRATEGY_DISPLAY then
      vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
    else
      local Popup = require("nui.popup")
      local ui = vim.tbl_deep_extend("keep", self.ui, {
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
          style = "rounded",
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
      local popup = Popup(ui)
      vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, lines)
      popup:mount()
    end
  end)
end

return CompletionAction
