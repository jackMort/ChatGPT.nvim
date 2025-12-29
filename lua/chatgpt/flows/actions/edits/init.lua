local classes = require("chatgpt.common.classes")
local BaseAction = require("chatgpt.flows.actions.base")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

local EditAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_DISPLAY = "display"

function EditAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_REPLACE
end

function EditAction:render_template()
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

function EditAction:get_params()
  return vim.tbl_extend("force", Config.options.openai_edit_params, self.params, {
    input = self:render_template(),
    instruction = self.params.instruction or "Apply the requested changes",
  })
end

function EditAction:run()
  vim.schedule(function()
    self:set_loading(true)

    local params = self:get_params()
    Api.edits(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end)
end

function EditAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)

    local bufnr = self:get_bufnr()
    local visual_lines, start_row, start_col, end_row, end_col = self:get_visual_selection(bufnr)
    local nlcount = Utils.count_newlines_at_end(table.concat(visual_lines, "\n"))
    local answer_nlfixed = Utils.replace_newlines_at_end(answer, nlcount)
    local lines = Utils.split_string_by_line(answer_nlfixed)
    vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
  end)
end

return EditAction
