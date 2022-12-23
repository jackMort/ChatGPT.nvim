local classes = require("chatgpt.common.classes")
local BaseAction = require("chatgpt.flows.actions.base")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

local CompletionAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_DISPLAY = "display"
local strategies = {
  STRATEGY_REPLACE,
  STRATEGY_DISPLAY,
}

function CompletionAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_REPLACE
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
  return vim.tbl_extend("force", Config.options.openai_params, self.params, { prompt = self:render_template() })
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
    local lines = Utils.split_string_by_line(answer)
    local start_row, start_col, end_row, end_col = self:get_visual_selection()

    if self.strategy == STRATEGY_REPLACE then
      vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
    else
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
    end
  end)
end

return CompletionAction
