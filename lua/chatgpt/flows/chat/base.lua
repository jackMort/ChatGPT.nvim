local classes = require("chatgpt.common.classes")
local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Settings = require("chatgpt.settings")
local Help = require("chatgpt.help")
local Sessions = require("chatgpt.flows.chat.sessions")
local Utils = require("chatgpt.utils")
local Signs = require("chatgpt.signs")
local Spinner = require("chatgpt.spinner")
local Session = require("chatgpt.flows.chat.session")
local SystemWindow = require("chatgpt.flows.chat.system_window")

QUESTION, ANSWER, SYSTEM = 1, 2, 3
ROLE_ASSISTANT = "assistant"
ROLE_SYSTEM = "system"
ROLE_USER = "user"

local Chat = classes.class()

function Chat:init()
  self.input_extmark_id = nil

  self.active_panel = nil
  self.selected_message_nsid = vim.api.nvim_create_namespace("ChatGPTNSSM")

  -- quit indicator
  self.active = true

  -- UI ELEMENTS
  self.layout = nil
  self.chat_panel = nil
  self.chat_input = nil
  self.chat_window = nil
  self.sessions_panel = nil
  self.open_extra_panels = {} -- track open panels
  self.settings_panel = nil
  self.help_panel = nil
  self.system_role_panel = nil

  -- UI OPEN INDICATORS
  self.settings_open = false
  self.system_role_open = false

  self.is_streaming_response = false

  self.prompt_lines = 1

  self.display_mode = Config.options.popup_layout.default
  self.params = Config.options.openai_params

  self.session = Session.latest()
  self.selectedIndex = 0
  self.role = ROLE_USER
  self.messages = {}
  self.spinner = Spinner:new(function(state)
    vim.schedule(function()
      self:set_lines(-2, -1, false, { state .. " " .. Config.options.chat.loading_text })
      self:display_input_suffix(state)
    end)
  end)
end

function Chat:welcome()
  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:set_system_message(nil, true)

  if #self.session.conversation > 0 then
    for idx, item in ipairs(self.session.conversation) do
      if item.type == SYSTEM then
        self:set_system_message(item.text, true)
      else
        self:_add(item.type, item.text, item.usage, idx)
      end
    end
  end

  if #self.session.conversation == 0 or (#self.session.conversation == 1 and self.system_message ~= nil) then
    local lines = Utils.split_string_by_line(Config.options.chat.welcome_message)
    self:set_lines(0, 0, false, lines)
    for line_num = 0, #lines do
      self:add_highlight("ChatGPTWelcome", line_num, 0, -1)
    end
  end
  self:render_role()
end

function Chat:render_role()
  if self.role_extmark_id ~= nil then
    vim.api.nvim_buf_del_extmark(self.chat_input.bufnr, Config.namespace_id, self.role_extmark_id)
  end

  self.role_extmark_id = vim.api.nvim_buf_set_extmark(self.chat_input.bufnr, Config.namespace_id, 0, 0, {
    virt_text = {
      { Config.options.chat.border_left_sign, "ChatGPTTotalTokensBorder" },
      {
        string.upper(self.role),
        "ChatGPTTotalTokens",
      },
      { Config.options.chat.border_right_sign, "ChatGPTTotalTokensBorder" },
      { " " },
    },
    virt_text_pos = "right_align",
  })
end

function Chat:set_system_message(msg, skip_session_add)
  self.system_message = msg
  if msg == nil then
    self.system_role_panel:set_text({})
    return
  end

  if not skip_session_add then
    self.session:add_item({
      type = SYSTEM,
      text = msg,
      usage = {},
    })
  else
    self.system_role_panel:set_text(Utils.split_string_by_line(msg))
  end
end

function Chat:new_session()
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, Config.namespace_id, 0, -1)

  self.session = Session:new()
  self.session:save()

  self.system_message = nil
  self.system_role_panel:set_text({})
  self:welcome()
end

function Chat:set_session(session)
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, Config.namespace_id, 0, -1)

  self.session = session

  self.messages = {}
  self.selectedIndex = 0
  self:set_lines(0, -1, false, {})
  self:set_cursor({ 1, 0 })
  self:welcome()
end

function Chat:isBusy()
  return self.spinner:is_running() or self.is_streaming_response
end

function Chat:add(type, text, usage)
  local idx = self.session:add_item({
    type = type,
    text = text,
    usage = usage,
  })
  self:_add(type, text, usage, idx)
  self:render_role()
end

function Chat:_add(type, text, usage, idx)
  if not self:is_buf_exists() then
    return
  end

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  local lines = {}
  local nr_of_lines = 0
  for line in string.gmatch(text, "[^\n]+") do
    nr_of_lines = nr_of_lines + 1
    table.insert(lines, line)
  end

  table.insert(self.messages, {
    idx = idx,
    usage = usage or {},
    type = type,
    text = text,
    lines = lines,
    nr_of_lines = nr_of_lines,
    start_line = start_line,
    end_line = start_line + nr_of_lines - 1,
  })
  self.selectedIndex = self.selectedIndex + 1
  self:renderLastMessage()
end

function Chat:addQuestion(text)
  self:add(self.role == ROLE_USER and QUESTION or ANSWER, text)
end

function Chat:addSystem(text)
  self:add(SYSTEM, text)
end

function Chat:addAnswer(text, usage)
  self:add(ANSWER, text, usage)
end

function Chat:addAnswerPartial(text, state)
  if state == "ERROR" then
    return self:addAnswer(text, {})
  end

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  if state == "END" then
    local usage = {}
    local idx = self.session:add_item({
      type = ANSWER,
      text = text,
      usage = usage,
    })

    local lines = {}
    local nr_of_lines = 0
    for line in string.gmatch(text, "[^\n]+") do
      nr_of_lines = nr_of_lines + 1
      table.insert(lines, line)
    end

    local end_line = start_line + nr_of_lines - 1
    table.insert(self.messages, {
      idx = idx,
      usage = usage or {},
      type = ANSWER,
      text = text,
      lines = lines,
      nr_of_lines = nr_of_lines,
      start_line = start_line,
      end_line = end_line,
    })
    self.selectedIndex = self.selectedIndex + 1

    if self.chat_window.bufnr ~= nil then
      vim.api.nvim_buf_set_lines(self.chat_window.bufnr, -1, -1, false, { "", "" })
      Signs.set_for_lines(self.chat_window.bufnr, start_line, end_line, "chat")
    end

    self.is_streaming_response = false
  end

  if state == "START" then
    self.is_streaming_response = true

    self:stopSpinner()
    self:set_lines(-2, -1, false, { "" })
    if self.chat_input.bufnr ~= nil then
      vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
    end
  end

  if state == "START" or state == "CONTINUE" then
    local lines = vim.split(text, "\n", {})
    local length = #lines
    local buffer = self.chat_window.bufnr
    local win = self.chat_window.winid

    if buffer == nil then
      return
    end

    for i, line in ipairs(lines) do
      local currentLine = vim.api.nvim_buf_get_lines(buffer, -2, -1, false)[1]
      vim.api.nvim_buf_set_lines(buffer, -2, -1, false, { currentLine .. line })

      local last_line_num = vim.api.nvim_buf_line_count(buffer)
      Signs.set_for_lines(self.chat_window.bufnr, start_line, last_line_num - 1, "chat")
      if i == length and i > 1 then
        vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
      end
      if self:is_buf_visiable() then
        vim.api.nvim_win_set_cursor(win, { last_line_num, 0 })
      end
    end
  end
end

function Chat:get_total_tokens()
  local total_tokens = 0
  for i = 1, #self.messages, 1 do
    local tokens = self.messages[i].usage.total_tokens
    if tokens ~= nil then
      total_tokens = total_tokens + tokens
    end
  end
  return total_tokens
end

function Chat:next()
  local count = self:count()
  if self.selectedIndex < count then
    self.selectedIndex = self.selectedIndex + 1
  else
    self.selectedIndex = 1
  end
  self:show_message_selection()
end

function Chat:prev()
  local count = self:count()
  if self.selectedIndex > 1 then
    self.selectedIndex = self.selectedIndex - 1
  else
    self.selectedIndex = count
  end
  self:show_message_selection()
end

function Chat:show_message_selection()
  local msg = self:getSelected()
  if msg == nil then
    return
  end

  self:set_cursor({ msg.start_line + 1, 0 })
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, self.selected_message_nsid, 0, -1)
  vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
    end_col = 0,
    end_row = msg.end_line + 1,
    hl_group = "ChatGPTSelectedMessage",
    hl_eol = true,
  })
  self:render_message_actions()
end

function Chat:hide_message_selection()
  vim.api.nvim_buf_clear_namespace(self.chat_window.bufnr, self.selected_message_nsid, 0, -1)
end

function Chat:getSelected()
  return self.messages[self.selectedIndex]
end

function Chat:delete_message()
  local selected_index = self.selectedIndex
  local msg = self:getSelected()
  self.session:delete_by_index(msg.idx)

  if msg.extmark_id then
    vim.api.nvim_buf_del_extmark(self.chat_window.bufnr, Config.namespace_id, msg.extmark_id)
  end

  self:welcome()
  if selected_index > 1 then
    self.selectedIndex = selected_index - 1
    local current_msg = self:getSelected()
    self:set_cursor({ current_msg.start_line + 1, 0 })
  end
  self:show_message_selection()
end

function Chat:render_message_actions()
  local msg = self:getSelected()
  if msg ~= nil then
    vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
      virt_text = {
        {
          " Delete (" .. Config.options.chat.keymaps.delete_message .. ") ",
          "ChatGPTMessageAction",
        },
        { " ", "ChatGPTSelectedMessage" },
      },
      virt_text_pos = "right_align",
    })

    -- vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, self.selected_message_nsid, msg.start_line, 0, {
    --   virt_text = {
    --     { "  ", "ChatGPTSelectedMessage" },
    --     {
    --       " Edit (" .. Config.options.chat.keymaps.edit_message .. ") ",
    --       "ChatGPTMessageAction",
    --     },
    --     { " ", "ChatGPTSelectedMessage" },
    --   },
    --   virt_text_pos = "right_align",
    -- })
  end
end

function Chat:getSelectedCode()
  local msg = self:getSelected()
  local text = msg.text
  -- Iterate through all code blocks in the message using a regular expression pattern
  local lastCodeBlock
  for codeBlock in text:gmatch("```.-```%s*") do
    lastCodeBlock = codeBlock
  end
  -- If a code block was found, strip the delimiters and return the code
  if lastCodeBlock then
    local index = string.find(lastCodeBlock, "\n")
    if index ~= nil then
      lastCodeBlock = string.sub(lastCodeBlock, index + 1)
    end
    return lastCodeBlock:gsub("```\n", ""):gsub("```", ""):match("^%s*(.-)%s*$")
  end
  return nil
end

function Chat:get_last_answer()
  for i = #self.messages, 1, -1 do
    if self.messages[i].type == ANSWER then
      return self.messages[i]
    end
  end
end

function Chat:renderLastMessage()
  self:stopSpinner()
  local msg = self:getSelected()

  local lines = {}
  for w in string.gmatch(msg.text, "[^\r\n]+") do
    table.insert(lines, w)
  end
  table.insert(lines, "")
  if msg.type == ANSWER then
    table.insert(lines, "")
  end

  local startIdx = self.selectedIndex == 1 and 0 or -2
  self:set_lines(startIdx, -1, false, lines)

  if msg.type == QUESTION then
    for index, _ in ipairs(lines) do
      self:add_highlight("ChatGPTQuestion", msg.start_line + index - 1, 0, -1)
    end

    pcall(
      vim.fn.sign_place,
      0,
      "chatgpt_ns",
      "chatgpt_question_sign",
      self.chat_window.bufnr,
      { lnum = msg.start_line + 1 }
    )
  else
    local total_tokens = msg.usage.total_tokens
    if total_tokens ~= nil then
      self.messages[self.selectedIndex].extmark_id =
        vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, Config.namespace_id, msg.end_line + 1, 0, {
          virt_text = {
            { Config.options.chat.border_left_sign, "ChatGPTTotalTokensBorder" },
            {
              "TOKENS: " .. msg.usage.total_tokens,
              "ChatGPTTotalTokens",
            },
            { Config.options.chat.border_right_sign, "ChatGPTTotalTokensBorder" },
            { " ", "" },
          },
          virt_text_pos = "right_align",
        })
    end

    Signs.set_for_lines(self.chat_window.bufnr, msg.start_line, msg.end_line, "chat")
  end

  if self.selectedIndex > 2 then
    self:set_cursor({ msg.end_line - 1, 0 })
  end
end

function Chat:showProgess()
  self.spinner:start()
end

function Chat:stopSpinner()
  self.spinner:stop()
  self:display_input_suffix()
end

function Chat:toString()
  local str = ""
  for _, msg in pairs(self.messages) do
    str = str .. msg.text .. "\n"
  end
  return str
end

local function createContent(line)
  local extensions = { "%.jpeg", "%.jpg", "%.png", "%.gif", "%.bmp", "%.tif", "%.tiff", "%.webp" }
  for _, ext in ipairs(extensions) do
    if string.find(line:lower(), ext .. "$") then
      return { type = "image_url", image_url = line }
    end
  end
  return { type = "text", text = line }
end

function Chat:toMessages()
  local messages = {}
  if self.system_message ~= nil then
    table.insert(messages, { role = "system", content = self.system_message })
  end

  for _, msg in pairs(self.messages) do
    local role = "user"
    if msg.type == SYSTEM then
      role = "system"
    elseif msg.type == ANSWER then
      role = "assistant"
    end
    local content = {}
    if Utils.collapsed_openai_params(self.params).model == "gpt-4-vision-preview" then
      for _, line in ipairs(msg.lines) do
        table.insert(content, createContent(line))
      end
    else
      content = msg.text
    end
    table.insert(messages, { role = role, content = content })
  end
  return messages
end

function Chat:count()
  local count = 0
  for _ in pairs(self.messages) do
    count = count + 1
  end
  return count
end

function Chat:is_buf_exists()
  return vim.fn.bufexists(self.chat_window.bufnr) == 1
end

function Chat:is_buf_visiable()
  -- Get all windows in the current tab
  local wins = vim.api.nvim_tabpage_list_wins(0)
  -- Traverse the window list to determine whether the buffer of chat_window is visible in the window
  local visible = false
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == self.chat_window.bufnr then
      visible = true
      break
    end
  end
  return visible
end

function Chat:set_lines(start_idx, end_idx, strict_indexing, lines)
  if self:is_buf_exists() then
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.chat_window.bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", false)
  end
end

function Chat:add_highlight(hl_group, line, col_start, col_end)
  if self:is_buf_exists() then
    vim.api.nvim_buf_add_highlight(self.chat_window.bufnr, -1, hl_group, line, col_start, col_end)
  end
end

function Chat:set_cursor(pos)
  if self:is_buf_visiable() then
    pcall(vim.api.nvim_win_set_cursor, self.chat_window.winid, pos)
  end
end

function Chat:get_width()
  if self:is_buf_exists() then
    return vim.api.nvim_win_get_width(self.chat_window.winid)
  end
end

function Chat:display_input_suffix(suffix)
  if self.chat_input.bufnr == nil then
    return
  end

  if self.extmark_id then
    vim.api.nvim_buf_del_extmark(self.chat_input.bufnr, Config.namespace_id, self.extmark_id)
  end

  if suffix then
    self.extmark_id = vim.api.nvim_buf_set_extmark(self.chat_input.bufnr, Config.namespace_id, 0, -1, {
      virt_text = {
        { Config.options.chat.border_left_sign, "ChatGPTTotalTokensBorder" },
        { "" .. suffix, "ChatGPTTotalTokens" },
        { Config.options.chat.border_right_sign, "ChatGPTTotalTokensBorder" },
        { " ", "" },
      },
      virt_text_pos = "right_align",
    })
  end
end

function Chat:scroll(direction)
  local speed = vim.api.nvim_win_get_height(self.chat_window.winid) / 2
  local input = direction > 0 and [[]] or [[]]
  local count = math.floor(speed)

  vim.api.nvim_win_call(self.chat_window.winid, function()
    vim.cmd([[normal! ]] .. count .. input)
  end)
end

function Chat:map(keys, fn, windows, modes)
  if windows == nil or next(windows) == nil then
    windows = {
      self.help_panel,
      self.settings_panel,
      self.sessions_panel,
      self.system_role_panel,
      self.chat_input,
      self.chat_window,
    }
  end

  if modes == nil or next(modes) == nil then
    modes = { "n", "i" }
  end

  if type(keys) ~= "table" then
    keys = { keys }
  end

  for _, popup in ipairs(windows) do
    for _, mode in ipairs(modes) do
      for _, key in ipairs(keys) do
        popup:map(mode, key, fn, {})
      end
    end
  end
end

function Chat:set_active_panel(panel)
  vim.api.nvim_set_current_win(panel.winid)
  self.active_panel = panel
  Utils.change_mode_to_normal()

  if self.active_panel == self.chat_window then
    self:show_message_selection()
  else
    self:hide_message_selection()
  end
end

function Chat:get_layout_params()
  local lines_height = vim.api.nvim_get_option("lines")
  local statusline_height = vim.o.laststatus == 0 and 0 or 1 -- height of the statusline if present
  local cmdline_height = vim.o.cmdheight -- height of the cmdline if present
  local tabline_height = vim.o.showtabline == 0 and 0 or 1 -- height of the tabline if present
  local total_height = lines_height
  local used_height = statusline_height + cmdline_height + tabline_height
  local layout_height = total_height - used_height
  local starting_row = tabline_height == 0 and 0 or 1

  local width = Utils.calculate_percentage_width(Config.options.popup_layout.right.width)
  if #self.open_extra_panels > 0 then
    width = width + 40
  end

  local right_layout_config = {
    relative = "editor",
    position = {
      row = starting_row,
      col = "100%",
    },
    size = {
      width = width,
      height = layout_height,
    },
  }

  local center_layout_config = {
    relative = "editor",
    position = "50%",
    size = {
      width = Config.options.popup_layout.center.width,
      height = Config.options.popup_layout.center.height,
    },
  }

  local config = self.display_mode == "right" and right_layout_config or center_layout_config

  local left_layout = Layout.Box(self.chat_window, { grow = 1 })
  if self.system_role_open then
    left_layout = Layout.Box({
      Layout.Box(self.system_role_panel, { size = self.display_mode == "center" and 33 or 10 }),
      Layout.Box(self.chat_window, { grow = 1 }),
    }, { dir = self.display_mode == "center" and "row" or "col", grow = 1 })
  end

  local box = Layout.Box({
    left_layout,
    Layout.Box(self.chat_input, { size = (self.chat_input.border._.style == "none" and 0 or 2) + self.prompt_lines }),
  }, { dir = "col" })

  if #self.open_extra_panels > 0 then
    local extra_boxes = function()
      local box_size = (100 / #self.open_extra_panels) .. "%"
      local boxes = {}
      for i, panel in ipairs(self.open_extra_panels) do
        -- for the last panel, make it grow to fill the remaining space
        if i == #self.open_extra_panels then
          table.insert(boxes, Layout.Box(panel, { grow = 1 }))
        else
          table.insert(boxes, Layout.Box(panel, { size = box_size }))
        end
      end
      return Layout.Box(boxes, { dir = "col", size = 40 })
    end
    box = Layout.Box({
      Layout.Box({
        left_layout,
        Layout.Box(
          self.chat_input,
          { size = (self.chat_input.border._.style == "none" and 0 or 2) + self.prompt_lines }
        ),
      }, { dir = "col", grow = 1 }),
      extra_boxes(),
    }, { dir = "row" })
  end

  return config, box
end

function Chat:open()
  local displayed_params = Utils.table_shallow_copy(self.params)
  -- if the param is decided by a function and not constant, write <dynamic> for now
  -- TODO: if the current model should be displayed, the settings_panel would
  -- have to be constantly modified or rewritten to be able to manage a function
  -- returning the model as well
  for key, value in pairs(self.params) do
    if type(value) == "function" then
      displayed_params[key] = "<dynamic>"
    end
  end
  self.settings_panel = Settings.get_settings_panel("chat_completions", displayed_params)
  self.help_panel = Help.get_help_panel("chat")
  self.sessions_panel = Sessions.get_panel(function(session)
    self:set_session(session)
  end)
  self.chat_window = Popup(Config.options.popup_window)
  self.system_role_panel = SystemWindow({
    on_change = function(text)
      self:set_system_message(text)
    end,
  })
  self.stop = false
  self.should_stop = function()
    if self.stop then
      self.stop = false
      return true
    else
      return false
    end
  end
  self.chat_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    on_close = function()
      self:hide()
    end,
    on_change = vim.schedule_wrap(function(lines)
      if self.prompt_lines ~= #lines then
        self.prompt_lines = #lines
        self:redraw()
      end
    end),
    on_submit = function(value)
      -- clear input
      vim.api.nvim_buf_set_lines(self.chat_input.bufnr, 0, -1, false, { "" })

      if self:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end

      self:addQuestion(value)
      if self.role == ROLE_USER then
        self:showProgess()
        local params = vim.tbl_extend("keep", { stream = true, messages = self:toMessages() }, Settings.params)
        Api.chat_completions(params, function(answer, state)
          self:addAnswerPartial(answer, state)
        end, self.should_stop)
      end
    end,
  })

  self.layout = Layout(self:get_layout_params())

  -- yank last answer
  self:map(Config.options.chat.keymaps.yank_last, function()
    local msg = self:getSelected()
    vim.fn.setreg(Config.options.yank_register, msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { self.chat_input })

  -- yank last code
  self:map(Config.options.chat.keymaps.yank_last_code, function()
    local code = self:getSelectedCode()
    if code ~= nil then
      vim.fn.setreg(Config.options.yank_register, code)
      vim.notify("Successfully copied code to yank register!", vim.log.levels.INFO)
    else
      vim.notify("No code to yank!", vim.log.levels.WARN)
    end
  end, { self.chat_input })

  -- scroll down
  self:map(Config.options.chat.keymaps.scroll_down, function()
    self:scroll(1)
  end, { self.chat_input })

  -- next message
  self:map(Config.options.chat.keymaps.next_message, function()
    self:next()
  end, { self.chat_window }, { "n" })

  -- prev message
  self:map(Config.options.chat.keymaps.prev_message, function()
    self:prev()
  end, { self.chat_window }, { "n" })

  -- scroll up
  self:map(Config.options.chat.keymaps.scroll_up, function()
    self:scroll(-1)
  end, { self.chat_input })

  -- stop generating
  self:map(Config.options.chat.keymaps.stop_generating, function()
    self.stop = true
  end, { self.chat_input })

  -- close
  self:map(Config.options.chat.keymaps.close, function()
    self:hide()
    -- If current in insert mode, switch to insert mode
    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
  end)

  local function inTable(tbl, item)
    for key, value in pairs(tbl) do
      if value == item then
        return key
      end
    end
    return false
  end

  -- toggle settings
  self:map(Config.options.chat.keymaps.toggle_settings, function()
    local settings_open = inTable(self.open_extra_panels, self.settings_panel)
    if settings_open then
      table.remove(self.open_extra_panels, settings_open)
      settings_open = false
    else
      table.insert(self.open_extra_panels, self.settings_panel)
      settings_open = inTable(self.open_extra_panels, self.settings_panel)
    end
    self:redraw()

    if settings_open then
      vim.api.nvim_buf_set_option(self.open_extra_panels[settings_open].bufnr, "modifiable", false)
      vim.api.nvim_win_set_option(self.open_extra_panels[settings_open].winid, "cursorline", true)

      self:set_active_panel(self.open_extra_panels[settings_open])
    else
      self:set_active_panel(self.chat_input)
    end
  end)

  -- toggle help
  self:map(Config.options.chat.keymaps.toggle_help, function()
    local help_open = inTable(self.open_extra_panels, self.help_panel)
    if help_open then
      table.remove(self.open_extra_panels, help_open)
      help_open = false
    else
      table.insert(self.open_extra_panels, self.help_panel)
      help_open = inTable(self.open_extra_panels, self.help_panel)
    end
    self:redraw()

    if help_open then
      vim.api.nvim_buf_set_option(self.open_extra_panels[help_open].bufnr, "modifiable", false)
      vim.api.nvim_win_set_option(self.open_extra_panels[help_open].winid, "cursorline", true)

      self:set_active_panel(self.help_panel)
    else
      self:set_active_panel(self.chat_input)
    end
  end)

  -- toggle sessions
  self:map(Config.options.chat.keymaps.toggle_sessions, function()
    local sessions_open = inTable(self.open_extra_panels, self.sessions_panel)
    if sessions_open then
      table.remove(self.open_extra_panels, sessions_open)
    else
      table.insert(self.open_extra_panels, self.sessions_panel)
    end
    self:redraw()
  end)

  -- new session
  self:map(Config.options.chat.keymaps.new_session, function()
    self:new_session()
    Sessions:refresh()
  end, { self.settings_panel, self.chat_input, self.help_panel })

  -- cycle panes
  self:map(Config.options.chat.keymaps.cycle_windows, function()
    local in_table = inTable(self.open_extra_panels, self.active_panel)
    if not self.active_panel then
      self:set_active_panel(self.chat_input)
    end
    if self.active_panel == self.chat_input then
      if self.system_role_open then
        self:set_active_panel(self.system_role_panel)
      else
        self:set_active_panel(self.chat_window)
      end
    elseif self.active_panel == self.system_role_panel then
      self:set_active_panel(self.chat_window)
    elseif self.active_panel == self.chat_window then
      if #self.open_extra_panels > 0 then
        self:set_active_panel(self.open_extra_panels[1])
      else
        self:set_active_panel(self.chat_input)
      end
    elseif in_table then
      local next_index = (in_table + 1) % (#self.open_extra_panels + 1)
      if next_index == 0 then
        self:set_active_panel(self.chat_input)
      else
        self:set_active_panel(self.open_extra_panels[next_index])
      end
    else
      self:set_active_panel(self.chat_input)
    end
  end)

  -- cycle modes
  self:map(Config.options.chat.keymaps.cycle_modes, function()
    self.display_mode = self.display_mode == "right" and "center" or "right"
    self:redraw()
  end)

  -- toggle system
  self:map(Config.options.chat.keymaps.toggle_system_role_open, function()
    if self.system_role_open and self.active_panel == self.system_role_panel then
      self:set_active_panel(self.chat_input)
    end

    self.system_role_open = not self.system_role_open

    self:redraw()

    if self.system_role_open then
      self:set_active_panel(self.system_role_panel)
    end
  end)

  -- toggle role
  self:map(Config.options.chat.keymaps.toggle_message_role, function()
    self.role = self.role == ROLE_USER and ROLE_ASSISTANT or ROLE_USER
    self:render_role()
  end)

  -- draft message
  self:map(Config.options.chat.keymaps.draft_message, function()
    if self:isBusy() then
      vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(self.chat_input.bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")
    if #text > 0 then
      vim.api.nvim_buf_set_lines(self.chat_input.bufnr, 0, -1, false, { "" })
      self:add(self.role == ROLE_USER and QUESTION or ANSWER, text)
      if self.role ~= ROLE_USER then
        self.role = ROLE_USER
        self:render_role()
      end
    else
      vim.notify("Cannot add empty message.", vim.log.levels.WARN)
    end
  end)

  -- delete message
  self:map(Config.options.chat.keymaps.delete_message, function()
    if self:count() > 0 then
      self:delete_message()
    else
      vim.notify("Nothing selected.", vim.log.levels.WARN)
    end
  end, { self.chat_window }, { "n" })

  -- edit message
  self:map(Config.options.chat.keymaps.edit_message, function()
    if self:count() > 0 then
      self:edit_message()
    else
      vim.notify("Nothing selected.", vim.log.levels.WARN)
    end
  end, { self.chat_window }, { "n" })

  -- initialize
  self.layout:mount()
  self:welcome()

  local event = require("nui.utils.autocmd").event
  self.chat_input:on(event.QuitPre, function()
    self.active = false
  end)
end

function Chat:open_system_panel()
  self.system_role_open = true
  self:redraw()
  self:set_active_panel(self.system_role_panel)
end

function Chat:redraw(noinit)
  noinit = noinit or false
  self.layout:update(self:get_layout_params())
  if not noinit then
    self:welcome()
  end
end

function Chat:hide()
  self.layout:hide()
end

function Chat:show()
  self:redraw(true)
  self.layout:show()
end

function Chat:toggle()
  if self.layout.winid ~= nil then
    self:hide()
  else
    self:show()
  end
end

return Chat
