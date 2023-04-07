-- module represents a lua module for the plugin
local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Chat = require("chatgpt.chat")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Prompts = require("chatgpt.prompts")
local Edits = require("chatgpt.code_edits")
local Settings = require("chatgpt.settings")
local Sessions = require("chatgpt.flows.chat.sessions")
local Session = require("chatgpt.flows.chat.session")
local Actions = require("chatgpt.flows.actions")
local Tokens = require("chatgpt.flows.chat.tokens")
local CodeCompletions = require("chatgpt.flows.code_completions")
local Utils = require("chatgpt.utils")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

local prompt_lines = 1
local extmark_id = nil
local virt_text_len = 0
local open_chat = function()
  local chat, chat_input, layout, chat_window
  local settings_open = false
  local active_panel = chat_input

  local display_input_suffix = function(suffix)
    if extmark_id then
      vim.api.nvim_buf_del_extmark(chat_input.bufnr, namespace_id, extmark_id)
    end

    if not suffix then
      return
    end

    virt_text_len = #("" .. suffix) + 3
    extmark_id = vim.api.nvim_buf_set_extmark(chat_input.bufnr, namespace_id, 0, -1, {
      virt_text = {
        { "", "ChatGPTTotalTokensBorder" },
        { "" .. suffix, "ChatGPTTotalTokens" },
        { "", "ChatGPTTotalTokensBorder" },
        { " ", "" },
      },
      virt_text_pos = "right_align",
    })
  end
  local function display_total_tokens()
    local total_tokens = chat:get_total_tokens()
    display_input_suffix("TOKENS: " .. total_tokens .. " / PRICE: $" .. Tokens.usage_in_dollars(total_tokens))
  end

  local scroll_chat = function(direction)
    local speed = vim.api.nvim_win_get_height(chat_window.winid) / 2
    local input = direction > 0 and [[]] or [[]]
    local count = math.floor(speed)

    vim.api.nvim_win_call(chat_window.winid, function()
      vim.cmd([[normal! ]] .. count .. input)
    end)
  end

  local params = Config.options.openai_params
  local settings_panel = Settings.get_settings_panel("chat_completions", params)
  local sessions_panel = Sessions.get_panel(function(session)
    chat:set_session(session)
    display_total_tokens()
  end)
  chat_window = Popup(Config.options.popup_window)
  chat_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    on_close = function()
      chat:close()
      Api.close()
      layout:unmount()
    end,
    on_change = vim.schedule_wrap(function(lines)
      local max_length = Utils.max_line_length(lines)
      local win_width = vim.api.nvim_win_get_width(chat_input.winid)
      if max_length + virt_text_len > win_width - 3 then
        if extmark_id ~= nil then
          vim.api.nvim_buf_del_extmark(chat_input.bufnr, namespace_id, extmark_id)
          extmark_id = nil
        end
      elseif extmark_id == nil then
        display_total_tokens()
      end
      if prompt_lines ~= #lines then
        prompt_lines = #lines
        if not settings_open then
          layout:update(Layout.Box({
            Layout.Box(chat_window, { grow = 1 }),
            Layout.Box(chat_input, { size = 2 + prompt_lines }),
          }, { dir = "col" }))
          vim.api.nvim_set_current_win(chat_input.winid)
        else
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(chat_window, { grow = 1 }),
              Layout.Box(chat_input, { size = 2 + prompt_lines }),
            }, { dir = "col", grow = 1 }),
            Layout.Box({
              Layout.Box(settings_panel, { size = "30%" }),
              Layout.Box(sessions_panel, { grow = 1 }),
            }, { dir = "col", size = 40 }),
          }, { dir = "row" }))
        end
      end
    end),
    on_submit = vim.schedule_wrap(function(value)
      -- clear input
      vim.api.nvim_buf_set_lines(chat_input.bufnr, 0, -1, false, { "" })

      if chat:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end

      chat:addQuestion(value)
      chat:showProgess()

      local params = vim.tbl_extend("keep", { messages = chat:toMessages() }, Settings.params)
      Api.chat_completions(params, function(answer, usage)
        chat:addAnswer(answer, usage)
        display_total_tokens()
      end)
    end),
  })

  layout = Layout(
    Config.options.popup_layout,
    Layout.Box({
      Layout.Box(chat_window, { grow = 1 }),
      Layout.Box(chat_input, { size = 3 }),
    }, { dir = "col", grow = 1 })
  )

  local keys = function(key, fn)
    for _, mode in ipairs({ "n", "i" }) do
      chat_input:map(mode, key, fn)
    end
  end

  --
  -- add keymaps
  --
  -- yank last answer
  chat_input:map("i", Config.options.chat.keymaps.yank_last, function()
    local msg = chat:getSelected()
    vim.fn.setreg(Config.options.yank_register, msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { noremap = true })

  -- yank last code
  keys(Config.options.chat.keymaps.yank_last_code, function()
    local code = chat:getSelectedCode()
    if code ~= nil then
      vim.fn.setreg(Config.options.yank_register, code)
      vim.notify("Successfully copied code to yank register!", vim.log.levels.INFO)
    else
      vim.notify("No code to yank!", vim.log.levels.WARN)
    end
  end)

  -- scroll down
  chat_input:map("i", Config.options.chat.keymaps.scroll_down, function()
    scroll_chat(1)
  end, { noremap = true, silent = true })

  -- scroll up
  chat_input:map("i", Config.options.chat.keymaps.scroll_up, function()
    scroll_chat(-1)
  end, { noremap = true, silent = true })

  -- close
  local close_keymaps = Config.options.chat.keymaps.close
  if type(close_keymaps) ~= "table" then
    close_keymaps = { close_keymaps }
  end

  for _, keymap in ipairs(close_keymaps) do
    chat_input:map("i", keymap, function()
      chat_input.input_props.on_close()
    end, { noremap = true, silent = true })

    chat_input:map("n", keymap, function()
      chat_input.input_props.on_close()
    end, { noremap = true, silent = true })
  end

  -- toggle settings
  for _, popup in ipairs({ settings_panel, chat_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.chat.keymaps.toggle_settings, function()
        if settings_open then
          layout:update(Layout.Box({
            Layout.Box(chat_window, { grow = 1 }),
            Layout.Box(chat_input, { size = 2 + prompt_lines }),
          }, { dir = "col" }))
          vim.api.nvim_set_current_win(chat_input.winid)
        else
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(chat_window, { grow = 1 }),
              Layout.Box(chat_input, { size = 2 + prompt_lines }),
            }, { dir = "col", grow = 1 }),
            Layout.Box({
              Layout.Box(settings_panel, { size = "30%" }),
              Layout.Box(sessions_panel, { grow = 1 }),
            }, { dir = "col", size = 40 }),
          }, { dir = "row" }))

          vim.api.nvim_set_current_win(settings_panel.winid)
          vim.api.nvim_buf_set_option(settings_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(settings_panel.winid, "cursorline", true)
          Utils.change_mode_to_normal()
          active_panel = settings_panel
        end
        settings_open = not settings_open
      end, {})
    end
  end

  -- toggle settings
  for _, popup in ipairs({ settings_panel, chat_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.chat.keymaps.new_session, function()
        chat:new_session()
        Sessions:refresh()
        display_total_tokens()
      end, {})
    end
  end

  -- cycle panes
  for _, popup in ipairs({ settings_panel, sessions_panel, chat_input, chat_window }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.chat.keymaps.cycle_windows, function()
        if active_panel == settings_panel then
          vim.api.nvim_set_current_win(sessions_panel.winid)
          active_panel = sessions_panel
          Utils.change_mode_to_normal()
        elseif active_panel == sessions_panel then
          vim.api.nvim_set_current_win(chat_input.winid)
          active_panel = chat_input
          Utils.change_mode_to_insert()
        elseif active_panel == chat_input then
          vim.api.nvim_set_current_win(chat_window.winid)
          active_panel = chat_window
          Utils.change_mode_to_normal()
        elseif active_panel == chat_window and settings_open == true then
          vim.api.nvim_set_current_win(settings_panel.winid)
          active_panel = settings_panel
          Utils.change_mode_to_normal()
        else
          vim.api.nvim_set_current_win(chat_input.winid)
          active_panel = chat_input
          Utils.change_mode_to_insert()
        end
      end, {})
    end
  end

  -- mount chat component
  layout:mount()

  -- initialize chat
  chat = Chat:new(chat_window.bufnr, chat_window.winid, display_input_suffix)

  -- set custom filetype
  vim.api.nvim_buf_set_option(chat_window.bufnr, "filetype", Config.options.popup_window.filetype)

  return chat, chat_input, chat_window, display_total_tokens
end

M.openChat = function()
  local chat, _, _, display_total_tokens = open_chat()
  chat:welcome()
  display_total_tokens()
end

M.open_chat_with_awesome_prompt = function()
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      -- create new named session
      local session = Session.new({ name = act })
      session:save()

      local chat, _, chat_window, display_total_tokens = open_chat()
      -- TODO: dry
      chat_window.border:set_text("top", " ChatGPT - Acts as " .. act .. " ", "center")

      chat:addSystem(prompt)
      chat:showProgess()

      local params = vim.tbl_extend("keep", { messages = chat:toMessages() }, Settings.params)
      Api.chat_completions(params, function(answer, usage)
        chat:addAnswer(answer, usage)
        display_total_tokens()
      end)
    end),
  })
end

M.edit_with_instructions = Edits.edit_with_instructions
M.run_action = Actions.run_action
M.complete_code = CodeCompletions.complete

return M
