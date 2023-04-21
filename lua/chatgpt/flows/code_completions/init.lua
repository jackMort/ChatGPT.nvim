local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Signs = require("chatgpt.signs")
local Spinner = require("chatgpt.spinner")

local M = {}

local namespace_id = vim.api.nvim_create_namespace("ChatGPTCC")

M.complete = function()
  local buffer = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(buffer)

  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local start_row = cursor_position[1]
  local start_col = cursor_position[2]

  local prefix = table.concat(vim.api.nvim_buf_get_text(buffer, 0, 0, start_row - 1, start_col, {}), "\n")
  local suffix = table.concat(vim.api.nvim_buf_get_text(buffer, start_row - 1, 0, line_count - 1, 99999999, {}), "\n")

  local spinner = nil
  local extmark_id = nil
  local set_loading = function(loading)
    if loading then
      if not spinner then
        spinner = Spinner:new(function(state)
          vim.schedule(function()
            if extmark_id then
              vim.api.nvim_buf_del_extmark(buffer, namespace_id, extmark_id)
            end
            extmark_id = vim.api.nvim_buf_set_extmark(buffer, namespace_id, start_row - 1, 0, {
              virt_text = {
                {
                  state .. " loading completion ...                                                 ",
                  "ChatGPTCompletion",
                },
              },
              virt_text_pos = "overlay",
            })
          end)
        end, {
          animation_type_name = "dot",
        })
      end
      spinner:start()
    else
      spinner:stop()
      vim.api.nvim_buf_del_extmark(buffer, namespace_id, extmark_id)
    end
  end

  set_loading(true)

  Api.completions({
    model = "text-davinci-003",
    prompt = prefix,
    suffix = suffix,
    max_tokens = 2048,
    presence_penalty = 0.6,
  }, function(answer, usage)
    set_loading(false)
    local Popup = require("nui.popup")
    local lines = Utils.split_string_by_line(answer)

    local popup = Popup({
      position = 0,
      size = {
        width = 80,
        height = #lines + 1,
      },
      relative = {
        type = "buf",
        position = {
          row = start_row - 1,
          col = start_col,
        },
      },
      enter = true,
      focusable = false,
      border = {
        style = "none",
      },
      buf_options = {
        modifiable = false,
        readonly = true,
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    })

    local empty_lines = {}
    for i = 1, #lines - 1, 1 do
      table.insert(empty_lines, "")
    end

    vim.api.nvim_buf_set_lines(buffer, start_row, start_row, true, empty_lines)
    Signs.set_for_lines(buffer, start_row - 1, start_row - 1 + #lines - 1, "action")
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, lines)

    for i = 0, #lines - 1, 1 do
      vim.api.nvim_buf_add_highlight(buffer, namespace_id, "ChatGPTCompletion", start_row + i, 0, -1)
      vim.api.nvim_buf_add_highlight(popup.bufnr, namespace_id, "ChatGPTCompletion", i, 0, -1)
    end

    popup:map("n", "<Enter>", function()
      vim.api.nvim_buf_set_lines(buffer, start_row - 1, start_row - 1 + #lines, true, lines)
      Signs.del(buffer)
      popup:unmount()
      vim.api.nvim_win_set_cursor(0, { start_row + #lines - 1, 0 })
    end, { noremap = true, silent = true })

    popup:map("n", "<Esc>", function()
      vim.api.nvim_buf_set_lines(buffer, start_row - 1, start_row - 1 + #lines, true, { "" })
      Signs.del(buffer)
      popup:unmount()
    end, { noremap = true, silent = true })

    popup:mount()
  end)
end

M.fib = function() end

return M
