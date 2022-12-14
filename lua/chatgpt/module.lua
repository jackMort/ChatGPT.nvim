-- module represents a lua module for the plugin
local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Chat = require("chatgpt.chat")
local Api = require("chatgpt.api")

M.complete = function(config)
  local chat, input, layout, chat_window

  chat_window = Popup({
    border = {
      highlight = "FloatBorder",
      style = "rounded",
      text = {
        top = " ChatGPT ",
      },
    },
  })

  input = ChatInput({
    border = {
      highlight = "FloatBorder",
      style = "rounded",
      text = {
        top = " Prompt ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal",
    },
  }, {
    prompt = "  ",
    on_submit = vim.schedule_wrap(function(value)
      -- clear input
      vim.api.nvim_buf_set_lines(input.bufnr, 0, 1, false, { "" })

      chat:addQuestion(value)
      chat:showProgess()

      Api.completions(chat:toString(), function(answer)
        chat:addAnswer(answer)
      end)
    end),
  })

  layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = "80%",
        height = "80%",
      },
    },
    Layout.Box({
      Layout.Box(chat_window, { size = "90%" }),
      Layout.Box(input, { size = 3 }),
    }, { dir = "col" })
  )

  -- add keymapping
  input:map("i", "<C-y>", function()
    local msg = chat:getSelected()
    vim.fn.setreg("+", msg.text)
    vim.notify("Succesfully copied to yank register!", vim.log.levels.INFO)
  end, { noremap = true })

  -- mount chat component
  layout:mount()

  -- initialize chat
  chat = Chat:new(chat_window.bufnr, chat_window.winid)
  chat:welcome()
end

return M
