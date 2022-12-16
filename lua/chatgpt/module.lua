-- module represents a lua module for the plugin
local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Chat = require("chatgpt.chat")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Prompts = require("chatgpt.prompts")

local open_chat = function()
  local chat, chat_input, layout, chat_window

  local scroll_chat = function(direction)
    local speed = vim.api.nvim_win_get_height(chat_window.winid) / 2
    local input = direction > 0 and [[]] or [[]]
    local count = math.abs(speed)

    vim.api.nvim_win_call(chat_window.winid, function()
      vim.cmd([[normal! ]] .. count .. input)
    end)
  end

  chat_window = Popup(Config.options.chat_window)
  chat_input = ChatInput(Config.options.chat_input, {
    prompt = Config.options.chat_input.prompt,
    on_close = function()
      chat:close()
      Api.close()
    end,
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
      Layout.Box(chat_window, { grow = 1 }),
      Layout.Box(chat_input, { size = 3 }),
    }, { dir = "col" })
  )

  -- add keymapping
  local maps = Config.options.keymaps
  chat_input:map("i", maps.yank, function()
    local msg = chat:getSelected()
    local register = Config.options.default_register
    vim.fn.setreg(register, msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { noremap = true })

  chat_input:map("i", maps.scroll_down, function()
    scroll_chat(1)
  end, { noremap = true, silent = true })

  chat_input:map("i", maps.scroll_up, function()
    scroll_chat(-1)
  end, { noremap = true, silent = true })

  -- mount chat component
  layout:mount()

  -- initialize chat
  chat = Chat:new(chat_window.bufnr, chat_window.winid)
  return chat, chat_input, chat_window
end

M.openChat = function()
  local chat, _, _ = open_chat()
  chat:welcome()
end

M.open_chat_with_awesome_prompt = function()
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      local chat, _, chat_window = open_chat()
      -- TODO: dry
      chat_window.border:set_text("top", " ChatGPT - Acts as " .. act .. " ", "center")

      chat:addQuestion(prompt)
      chat:showProgess()

      Api.completions(chat:toString(), function(answer)
        chat:addAnswer(answer)
      end)
    end),
  })
end

return M
