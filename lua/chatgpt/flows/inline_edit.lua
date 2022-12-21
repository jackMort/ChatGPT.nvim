local M = {}

local Signs = require("chatgpt.signs")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Spinner = require("chatgpt.spinner")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

function M.run(opts)
  local prompt = opts.args
  if opts.range == 0 then
    print("no selection")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()

  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local start_row = start_pos[1] - 1
  local start_col = start_pos[2]

  local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")
  local end_row = end_pos[1] - 1
  local end_col = end_pos[2] + 1

  local start_line_length = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1]:len()
  start_col = math.min(start_col, start_line_length)

  local end_line_length = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]:len()
  end_col = math.min(end_col, end_line_length)

  Signs.set_for_lines(bufnr, start_row, end_row)
  local selected_text = table.concat(vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {}), "\n")

  local extmark_id
  local spinner = Spinner:new(function(state)
    vim.schedule(function()
      if extmark_id then
        vim.api.nvim_buf_del_extmark(bufnr, namespace_id, extmark_id)
      end

      extmark_id = vim.api.nvim_buf_set_extmark(bufnr, namespace_id, start_row, 0, {
        virt_text = {
          { "", "ChatGPTTotalTokensBorder" },
          { state .. " Processing, please wait ...", "ChatGPTTotalTokens" },
          { "", "ChatGPTTotalTokensBorder" },
          { " ", "" },
        },
        virt_text_pos = "eol",
      })
    end)
  end)
  spinner:start()

  local params = {
    model = "code-davinci-002",
    prompt = string.format(
      "-- lua\n\n %s\n\n-- An elaborate, high quality docstring for the above function\n--",
      selected_text
    ),
    temperature = 0,
    max_tokens = 150,
    top_p = 1,
    frequency_penalty = 0,
    presence_penalty = 0,
    stop = { "--" },
  }

  Api.completions(params, function(answer)
    spinner:stop()
    local lines = Utils.split_string_by_line(answer)
    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
    Signs.del(bufnr)
  end)
end

return M
