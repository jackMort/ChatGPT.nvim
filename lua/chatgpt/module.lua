-- module represents a lua module for the plugin
local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Chat = require("chatgpt.chat")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")

M.openChat = function()
  local chat, chat_input, layout, chat_window

  chat_window = Popup(Config.options.chat_window)
  chat_input = ChatInput(Config.options.chat_input, {
    prompt = Config.options.chat_input.prompt,
    on_submit = vim.schedule_wrap(function(value)
      if chat:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end
      -- clear input
      vim.api.nvim_buf_set_lines(chat_input.bufnr, 0, 1, false, { "" })

      chat:addQuestion(value)
      chat:showProgess()

      Api.completions(chat:toString(), function(answer)
        chat:addAnswer(answer)
      end)
    end),
  })

  layout = Layout(
    Config.options.chat_layout,
    Layout.Box({
      Layout.Box(chat_window, { size = "90%" }),
      Layout.Box(chat_input, { size = 3 }),
    }, { dir = "col" })
  )

  -- add keymapping
  chat_input:map("i", "<C-y>", function()
    local msg = chat:getSelected()
    vim.fn.setreg("+", msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { noremap = true })

  -- mount chat component
  layout:mount()

  -- initialize chat
  chat = Chat:new(chat_window.bufnr, chat_window.winid)
  chat:welcome()
end

return M
