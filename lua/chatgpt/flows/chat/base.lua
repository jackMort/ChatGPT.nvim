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
local Context = require("chatgpt.context")
local LspContext = require("chatgpt.context.lsp")
local ProjectContext = require("chatgpt.context.project")
local Hints = require("chatgpt.flows.chat.hints")

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
  self.hints_panel = nil

  -- UI OPEN INDICATORS
  self.settings_open = false
  self.system_role_open = false

  self.is_streaming_response = false
  self.is_streaming_response_lock = false

  self.prompt_lines = 1

  -- Input history
  self.input_history = {}
  self.history_index = 0
  self.current_input = ""

  -- Token count
  self.current_tokens = 0

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

  local system_message_absent = true
  if #self.session.conversation > 0 then
    for idx, item in ipairs(self.session.conversation) do
      if item.type == SYSTEM then
        system_message_absent = false
        self:set_system_message(item.text, true)
      else
        self:_add(item.type, item.text, item.usage, idx)
      end
    end
  end

  if system_message_absent then
    local default_system_message = Config.options.chat.default_system_message
    if default_system_message and #default_system_message > 0 then
      self:set_system_message(default_system_message, true)
    end
  end

  -- Show welcome message only in non-compact mode
  if not self:is_compact() then
    if #self.session.conversation == 0 or (#self.session.conversation == 1 and self.system_message ~= nil) then
      local lines = Utils.split_string_by_line(Config.options.chat.welcome_message)
      self:set_lines(0, 0, false, lines)
      for line_num = 0, #lines do
        self:add_highlight("ChatGPTWelcome", line_num, 0, -1)
      end
    end
  end
  self:render_role()
end

function Chat:render_role()
  if self.role_extmark_id ~= nil then
    vim.api.nvim_buf_del_extmark(self.chat_input.bufnr, Config.namespace_id, self.role_extmark_id)
  end

  local virt_text = {}

  -- Add token count if > 0
  if self.current_tokens > 0 then
    table.insert(virt_text, { Config.options.chat.border_left_sign, "ChatGPTTokensBorder" })
    table.insert(virt_text, { self.current_tokens .. " TOKENS", "ChatGPTTokens" })
    table.insert(virt_text, { Config.options.chat.border_right_sign, "ChatGPTTokensBorder" })
    table.insert(virt_text, { " " })
  end

  -- Add role
  table.insert(virt_text, { Config.options.chat.border_left_sign, "ChatGPTTotalTokensBorder" })
  table.insert(virt_text, { string.upper(self.role), "ChatGPTTotalTokens" })
  table.insert(virt_text, { Config.options.chat.border_right_sign, "ChatGPTTotalTokensBorder" })
  table.insert(virt_text, { " " })

  self.role_extmark_id = vim.api.nvim_buf_set_extmark(self.chat_input.bufnr, Config.namespace_id, 0, 0, {
    virt_text = virt_text,
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

function Chat:is_compact()
  return self.display_mode == "right"
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
    local spacing = self:is_compact() and 1 or (prev.type == ANSWER and 2 or 1)
    start_line = prev.end_line + spacing
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

function Chat:addQuestionWithContext(display_text, api_text)
  local type = self.role == ROLE_USER and QUESTION or ANSWER
  local idx = self.session:add_item({
    type = type,
    text = display_text,
    api_text = api_text, -- Store expanded version for API
    usage = {},
  })
  self:_add(type, display_text, {}, idx)
  -- Store api_text in the message for toMessages()
  if self.messages[self.selectedIndex] then
    self.messages[self.selectedIndex].api_text = api_text
  end
  self:render_role()
end

function Chat:addSystem(text)
  self:add(SYSTEM, text)
end

function Chat:addAnswer(text, usage)
  self:add(ANSWER, text, usage)
end

function Chat:addAnswerPartial(text, state)
  if state == "ERROR" then
    -- unlock first and then wirte answer
    self.is_streaming_response_lock = false
    return self:addAnswer(text, {})
  end

  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    local spacing = self:is_compact() and 1 or (prev.type == ANSWER and 2 or 1)
    start_line = prev.end_line + spacing
  end

  if state == "END" then
    -- unlock first and then wirte answer
    self.is_streaming_response_lock = false
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

    -- redraw make sure signs correct
    self:redraw()

    self.is_streaming_response = false
    self:update_hints()
  end

  if state == "START" then
    self.is_streaming_response = true
    self:update_hints()

    self:stopSpinner()
    self:set_lines(-2, -1, false, { "" })

    -- lock chat window buf
    self.is_streaming_response_lock = true
  end

  if state == "START" or state == "CONTINUE" then
    -- avoid unlocking caused by multi addAnswerPartial parallel
    self.is_streaming_response_lock = true

    local lines = vim.split(text, "\n", {})
    local length = #lines
    local buffer = self.chat_window.bufnr
    local win = self.chat_window.winid

    if buffer == nil then
      return
    end

    for i, line in ipairs(lines) do
      local currentLine = vim.api.nvim_buf_get_lines(buffer, -2, -1, false)[1]
      Utils.modify_buf(self.chat_window.bufnr, function(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, { currentLine .. line })
      end)

      local last_line_num = vim.api.nvim_buf_line_count(buffer)
      -- busy call Signs.set_for_lines will cause neovim to freeze, and it will be redraw after completion
      -- Signs.set_for_lines(self.chat_window.bufnr, start_line, last_line_num - 1, "chat")
      if i == length and i > 1 then
        Utils.modify_buf(self.chat_window.bufnr, function(bufnr)
          vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "" })
        end)
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

-- Get code block at cursor position in chat window
function Chat:get_code_at_cursor()
  if not self.chat_window or not self.chat_window.bufnr then
    return nil
  end

  local bufnr = self.chat_window.bufnr
  local cursor = vim.api.nvim_win_get_cursor(self.chat_window.winid)
  local cursor_line = cursor[1] - 1 -- 0-indexed

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Find code block boundaries around cursor
  local block_start = nil
  local block_end = nil
  local in_block = false

  for i, line in ipairs(lines) do
    local line_idx = i - 1
    if line:match("^```") then
      if not in_block then
        -- Start of block
        in_block = true
        block_start = line_idx
      else
        -- End of block
        block_end = line_idx
        -- Check if cursor is within this block
        if cursor_line >= block_start and cursor_line <= block_end then
          -- Extract code (skip first line with ```)
          local code_lines = {}
          for j = block_start + 2, block_end do -- +2 to skip ```lang line (1-indexed)
            table.insert(code_lines, lines[j])
          end
          return table.concat(code_lines, "\n")
        end
        in_block = false
        block_start = nil
      end
    end
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

-- Find all code block positions in the buffer
function Chat:get_code_block_positions()
  if not self.chat_window or not self.chat_window.bufnr then
    return {}
  end

  local bufnr = self.chat_window.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local positions = {}
  local in_block = false
  local block_start = nil

  for i, line in ipairs(lines) do
    if line:match("^```") then
      if not in_block then
        in_block = true
        block_start = i - 1 -- 0-indexed
      else
        -- End of block
        table.insert(positions, { start_line = block_start, end_line = i - 1 })
        in_block = false
        block_start = nil
      end
    end
  end

  return positions
end

-- Navigate to next code block
function Chat:next_code_block()
  local positions = self:get_code_block_positions()
  if #positions == 0 then
    vim.notify("No code blocks found", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.chat_window.winid)
  local current_line = cursor[1] - 1 -- 0-indexed

  for _, pos in ipairs(positions) do
    if pos.start_line > current_line then
      vim.api.nvim_win_set_cursor(self.chat_window.winid, { pos.start_line + 1, 0 })
      return
    end
  end

  -- Wrap to first code block
  vim.api.nvim_win_set_cursor(self.chat_window.winid, { positions[1].start_line + 1, 0 })
end

-- Navigate to previous code block
function Chat:prev_code_block()
  local positions = self:get_code_block_positions()
  if #positions == 0 then
    vim.notify("No code blocks found", vim.log.levels.INFO)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.chat_window.winid)
  local current_line = cursor[1] - 1 -- 0-indexed

  for i = #positions, 1, -1 do
    local pos = positions[i]
    if pos.start_line < current_line then
      vim.api.nvim_win_set_cursor(self.chat_window.winid, { pos.start_line + 1, 0 })
      return
    end
  end

  -- Wrap to last code block
  vim.api.nvim_win_set_cursor(self.chat_window.winid, { positions[#positions].start_line + 1, 0 })
end

-- Apply rich highlighting to message content (code blocks, inline code, @refs, markdown)
function Chat:highlight_message_content(lines, start_line)
  local bufnr = self.chat_window.bufnr
  local in_code_block = false
  local code_lang = nil

  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1

    -- Check for code block start/end
    local block_start = line:match("^```(%w*)")

    if block_start and not in_code_block then
      in_code_block = true
      code_lang = block_start ~= "" and block_start or nil
      -- Hide the ``` line and show language header instead
      local header_text = {}
      if code_lang then
        table.insert(header_text, { " LANGUAGE: " .. string.upper(code_lang) .. " ", "ChatGPTCodeLang" })
        table.insert(
          header_text,
          { " ────────────────── ", "ChatGPTCodeBlockHeader" }
        )
        table.insert(header_text, { "[y] copy", "Comment" })
      else
        table.insert(header_text, { " CODE ", "ChatGPTCodeLang" })
        table.insert(
          header_text,
          { " ────────────────── ", "ChatGPTCodeBlockHeader" }
        )
        table.insert(header_text, { "[y] copy", "Comment" })
      end
      vim.api.nvim_buf_set_extmark(bufnr, Config.namespace_id, line_num, 0, {
        virt_text = header_text,
        virt_text_pos = "overlay",
        hl_mode = "combine",
        virt_lines_above = true,
        virt_lines = { { { "", "" } } },
      })
      vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTCodeBlock", line_num, 0, -1)
    elseif in_code_block and line == "```" then
      in_code_block = false
      code_lang = nil
      -- Hide the closing ``` with a subtle separator
      vim.api.nvim_buf_set_extmark(bufnr, Config.namespace_id, line_num, 0, {
        virt_text = { { "───", "ChatGPTCodeBlockHeader" } },
        virt_text_pos = "overlay",
        end_col = 3,
        conceal = "",
      })
      vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTCodeBlock", line_num, 0, -1)
    elseif in_code_block then
      -- Check for diff highlighting inside diff blocks
      if code_lang == "diff" then
        if line:match("^%+") then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTDiffAdd", line_num, 0, -1)
        elseif line:match("^%-") then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTDiffDel", line_num, 0, -1)
        else
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTCodeBlock", line_num, 0, -1)
        end
      else
        vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTCodeBlock", line_num, 0, -1)
      end
    else
      -- Headers (# ## ###)
      if line:match("^#+%s") then
        vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTHeader", line_num, 0, -1)
      -- Horizontal rule (--- or ***)
      elseif line:match("^%-%-%-+%s*$") or line:match("^%*%*%*+%s*$") then
        vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTHRule", line_num, 0, -1)
      -- Blockquote (> text)
      elseif line:match("^>") then
        vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTBlockquote", line_num, 0, -1)
      else
        -- Bullet list markers (- or *)
        local bullet = line:match("^(%s*[%-%*]%s)")
        if bullet then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTListMarker", line_num, 0, #bullet)
        end

        -- Numbered list markers (1. 2. etc)
        local num_marker = line:match("^(%s*%d+%.%s)")
        if num_marker then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTListMarker", line_num, 0, #num_marker)
        end

        -- @references
        for ref in line:gmatch("@[^%s]+") do
          local s, e = line:find(ref, 1, true)
          if s then
            vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTContextRef", line_num, s - 1, e)
          end
        end

        -- Inline `code`
        local col = 1
        while true do
          local s, e = line:find("`[^`]+`", col)
          if not s then
            break
          end
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTInlineCode", line_num, s - 1, e)
          col = e + 1
        end

        -- **bold**
        col = 1
        while true do
          local s, e = line:find("%*%*[^%*]+%*%*", col)
          if not s then
            break
          end
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTBold", line_num, s - 1, e)
          col = e + 1
        end

        -- *italic* or _italic_
        col = 1
        while true do
          local s, e = line:find("%*[^%*]+%*", col)
          if not s then
            break
          end
          -- Skip if it's actually bold (**)
          if line:sub(s, s + 1) ~= "**" and (s == 1 or line:sub(s - 1, s - 1) ~= "*") then
            vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTItalic", line_num, s - 1, e)
          end
          col = e + 1
        end

        -- URLs (http:// or https://)
        col = 1
        while true do
          local s, e = line:find("https?://[^%s%)%]]+", col)
          if not s then
            break
          end
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTLink", line_num, s - 1, e)
          col = e + 1
        end

        -- Task lists - [x] done, - [ ] pending
        local task_done = line:match("^(%s*%-%s*%[x%])")
        if task_done then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTTaskDone", line_num, 0, #task_done)
        end
        local task_pending = line:match("^(%s*%-%s*%[%s*%])")
        if task_pending then
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTTaskPending", line_num, 0, #task_pending)
        end

        -- ~~strikethrough~~
        col = 1
        while true do
          local s, e = line:find("~~[^~]+~~", col)
          if not s then
            break
          end
          vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTStrikethrough", line_num, s - 1, e)
          col = e + 1
        end

        -- Markdown links [text](url)
        col = 1
        while true do
          local s, e = line:find("%[[^%]]+%]%([^%)]+%)", col)
          if not s then
            break
          end
          -- Find the split between text and url
          local text_end = line:find("%]%(", s)
          if text_end then
            vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTLinkText", line_num, s - 1, text_end)
            vim.api.nvim_buf_add_highlight(bufnr, Config.namespace_id, "ChatGPTLinkUrl", line_num, text_end, e)
          end
          col = e + 1
        end
      end
    end
  end
end

-- Add visual divider after answer messages
function Chat:add_message_divider(line_num)
  local bufnr = self.chat_window.bufnr
  local divider = string.rep("─", 60)
  vim.api.nvim_buf_set_extmark(bufnr, Config.namespace_id, line_num, 0, {
    virt_lines = { { { divider, "ChatGPTDivider" } } },
    virt_lines_above = false,
  })
end

-- Create folds for code blocks in the message
function Chat:create_code_folds(lines, start_line)
  if not self.chat_window or not self.chat_window.winid then
    return
  end

  local in_block = false
  local block_start = nil

  for i, line in ipairs(lines) do
    local line_num = start_line + i -- 1-indexed for fold commands

    if line:match("^```") then
      if not in_block then
        in_block = true
        block_start = line_num
      else
        -- End of block - create fold if block has content
        if line_num > block_start + 1 then
          pcall(function()
            vim.api.nvim_win_call(self.chat_window.winid, function()
              vim.cmd(block_start .. "," .. line_num .. "fold")
              -- Open the fold by default
              vim.cmd(block_start .. "foldopen")
            end)
          end)
        end
        in_block = false
        block_start = nil
      end
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
    -- Add sender indicator
    vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, Config.namespace_id, msg.start_line, 0, {
      virt_text = { { "You ", "ChatGPTSenderUser" } },
      virt_text_pos = "inline",
    })

    -- Apply base question styling
    for index, _ in ipairs(lines) do
      self:add_highlight("ChatGPTQuestion", msg.start_line + index - 1, 0, -1)
    end

    -- Apply rich highlighting (overrides base for specific patterns)
    self:highlight_message_content(lines, msg.start_line)

    pcall(
      vim.fn.sign_place,
      0,
      "chatgpt_ns",
      "chatgpt_question_sign",
      self.chat_window.bufnr,
      { lnum = msg.start_line + 1 }
    )
  else
    -- Add sender indicator
    vim.api.nvim_buf_set_extmark(self.chat_window.bufnr, Config.namespace_id, msg.start_line, 0, {
      virt_text = { { "Assistant ", "ChatGPTSenderAssistant" } },
      virt_text_pos = "inline",
    })

    -- Apply rich highlighting for answer (code blocks, inline code, @refs)
    self:highlight_message_content(lines, msg.start_line)

    -- Create folds for code blocks (open by default, user can close with zc)
    self:create_code_folds(lines, msg.start_line)

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

    -- Add divider after answer
    self:add_message_divider(msg.end_line)
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

  -- Build system message with optional project summary
  local system_content = self.system_message or ""
  if Config.options.context and Config.options.context.project and Config.options.context.project.auto_detect then
    local project_summary = ProjectContext.generate_summary()
    if project_summary then
      if system_content ~= "" then
        system_content = system_content .. "\n\n[Project: " .. project_summary .. "]"
      else
        system_content = "[Project: " .. project_summary .. "]"
      end
    end
  end

  if system_content ~= "" then
    table.insert(messages, { role = "system", content = system_content })
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
      -- Use api_text (expanded context) if available, otherwise use display text
      content = msg.api_text or msg.text
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
  if not self.is_streaming_response_lock then
    Utils.modify_buf(self.chat_window.bufnr, function(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, strict_indexing, lines)
    end)
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

  -- Update hints based on active panel
  self:update_hints()
end

function Chat:update_hints()
  if not self.hints_panel then
    return
  end

  local context = "default"
  if self.active_panel == self.chat_window then
    context = "chat_window"
  elseif self.active_panel == self.chat_input then
    context = self.is_streaming_response and "chat_input_streaming" or "chat_input"
  elseif self.active_panel == self.sessions_panel then
    context = "sessions_panel"
  elseif self.active_panel == self.settings_panel then
    context = "settings_panel"
  elseif self.active_panel == self.help_panel then
    context = "help_panel"
  elseif self.active_panel == self.system_role_panel then
    context = "system_role_panel"
  end

  Hints.update(context)
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

  local input_size = (self.chat_input.border._.style == "none" and 0 or 2) + self.prompt_lines

  local main_content
  if #self.open_extra_panels > 0 then
    local extra_boxes = function()
      local box_size = (100 / #self.open_extra_panels) .. "%"
      local boxes = {}
      for i, panel in ipairs(self.open_extra_panels) do
        if i == #self.open_extra_panels then
          table.insert(boxes, Layout.Box(panel, { grow = 1 }))
        else
          table.insert(boxes, Layout.Box(panel, { size = box_size }))
        end
      end
      return Layout.Box(boxes, { dir = "col", size = 40 })
    end
    local left_column = Layout.Box({
      left_layout,
      Layout.Box(self.chat_input, { size = input_size }),
    }, { dir = "col", grow = 1 })
    main_content = Layout.Box({
      left_column,
      extra_boxes(),
    }, { dir = "row", grow = 1 })
  else
    main_content = Layout.Box({
      left_layout,
      Layout.Box(self.chat_input, { size = input_size }),
    }, { dir = "col", grow = 1 })
  end

  -- Build final layout with hints at full width bottom (hidden in compact mode)
  local box
  if self.hints_panel and not self:is_compact() then
    box = Layout.Box({
      main_content,
      Layout.Box(self.hints_panel, { size = 1 }),
    }, { dir = "col" })
  else
    box = main_content
  end

  return config, box
end

function Chat:open()
  -- Store original buffer for context commands
  self.original_bufnr = vim.api.nvim_get_current_buf()

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
  self.settings_panel = Settings.get_settings_panel("chat_completions", displayed_params, self.session.name)
  self.help_panel = Help.get_help_panel("chat")
  self.sessions_panel = Sessions.get_panel(function(session)
    self:set_session(session)
  end)
  self.chat_window = Popup(Config.options.popup_window)
  vim.api.nvim_buf_set_option(self.chat_window.bufnr, "modifiable", false)
  self.system_role_panel = SystemWindow({
    on_change = function(text)
      self:set_system_message(text)
    end,
  })
  if Config.options.chat.show_hints then
    self.hints_panel = Hints.get_panel()
  end
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
      -- Calculate tokens (~1.3 tokens per word)
      local text = table.concat(lines, "\n")
      local word_count = 0
      for _ in text:gmatch("%S+") do
        word_count = word_count + 1
      end
      self.current_tokens = math.ceil(word_count * 1.3)
      self:render_role()

      local new_lines = math.max(1, #lines)
      if self.prompt_lines ~= new_lines then
        self.prompt_lines = new_lines
        self:redraw()
        -- After redraw, scroll to show all content from top
        vim.schedule(function()
          if self.chat_input and self.chat_input.winid and vim.api.nvim_win_is_valid(self.chat_input.winid) then
            local cursor = vim.api.nvim_win_get_cursor(self.chat_input.winid)
            vim.api.nvim_win_call(self.chat_input.winid, function()
              -- Scroll to top first, then back to cursor
              vim.cmd("normal! gg0")
              vim.api.nvim_win_set_cursor(0, cursor)
            end)
          end
        end)
      end
    end),
    on_submit = function(value)
      -- clear input
      Utils.modify_buf(self.chat_input.bufnr, function(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
      end)

      if self:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end

      -- Save to history
      if value and value ~= "" then
        table.insert(self.input_history, value)
        self.history_index = 0
        self.current_input = ""
      end

      -- Expand @refs in message for API, keep original for display
      local api_message, display_message = Context.expand_refs(value)
      Context.clear()

      -- Store expanded message for API, display shows @refs inline
      self:addQuestionWithContext(display_message, api_message)
      if self.role == ROLE_USER then
        self:showProgess()
        local params = vim.tbl_extend("keep", { stream = true, messages = self:toMessages() }, self.params)
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

  -- next code block
  self:map(Config.options.chat.keymaps.next_code_block, function()
    self:next_code_block()
  end, { self.chat_window }, { "n" })

  -- prev code block
  self:map(Config.options.chat.keymaps.prev_code_block, function()
    self:prev_code_block()
  end, { self.chat_window }, { "n" })

  -- yank code under cursor
  self:map(Config.options.chat.keymaps.yank_code, function()
    local code = self:get_code_at_cursor()
    if code then
      vim.fn.setreg(Config.options.yank_register, code)
      vim.notify("Code copied!", vim.log.levels.INFO)
    else
      vim.notify("No code block at cursor", vim.log.levels.WARN)
    end
  end, { self.chat_window }, { "n" })

  -- toggle fold
  self:map(Config.options.chat.keymaps.toggle_fold, function()
    pcall(vim.cmd, "normal! za")
  end, { self.chat_window }, { "n" })

  -- scroll up
  self:map(Config.options.chat.keymaps.scroll_up, function()
    self:scroll(-1)
  end, { self.chat_input })

  -- stop generating
  self:map(Config.options.chat.keymaps.stop_generating, function()
    self.stop = true
  end, { self.chat_input })

  -- history: previous (up arrow)
  self:map("<Up>", function()
    if #self.input_history == 0 then
      return
    end
    -- Save current input if starting to navigate
    if self.history_index == 0 then
      local lines = vim.api.nvim_buf_get_lines(self.chat_input.bufnr, 0, -1, false)
      self.current_input = table.concat(lines, "\n")
    end
    -- Move back in history
    if self.history_index < #self.input_history then
      self.history_index = self.history_index + 1
      local history_entry = self.input_history[#self.input_history - self.history_index + 1]
      Utils.modify_buf(self.chat_input.bufnr, function(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(history_entry, "\n"))
      end)
    end
  end, { self.chat_input }, { "i", "n" })

  -- history: next (down arrow)
  self:map("<Down>", function()
    if self.history_index == 0 then
      return
    end
    -- Move forward in history
    self.history_index = self.history_index - 1
    local text
    if self.history_index == 0 then
      text = self.current_input
    else
      text = self.input_history[#self.input_history - self.history_index + 1]
    end
    Utils.modify_buf(self.chat_input.bufnr, function(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n"))
    end)
  end, { self.chat_input }, { "i", "n" })

  -- Helper to insert text at cursor in input buffer
  local function insert_at_cursor(text)
    if self.chat_input and self.chat_input.bufnr and vim.api.nvim_buf_is_valid(self.chat_input.bufnr) then
      vim.schedule(function()
        if self.chat_input.winid and vim.api.nvim_win_is_valid(self.chat_input.winid) then
          vim.api.nvim_set_current_win(self.chat_input.winid)
          vim.cmd("startinsert!")
          vim.api.nvim_put({ text .. " " }, "c", true, true)
        end
      end)
    end
  end

  -- @ context autocomplete
  self:map("@", function()
    vim.ui.select({
      { label = "LSP Symbol", value = "lsp" },
      { label = "Project Context", value = "project" },
      { label = "File", value = "file" },
      { label = "Git Diff", value = "diff" },
    }, {
      prompt = "Add Context:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if not choice then
        return
      end

      if choice.value == "lsp" then
        -- Add LSP context from original buffer
        if self.original_bufnr and vim.api.nvim_buf_is_valid(self.original_bufnr) then
          vim.api.nvim_set_current_buf(self.original_bufnr)
          LspContext.get_context(function(item)
            if item then
              local ref = Context.make_ref(item)
              Context.add(ref, item)
              insert_at_cursor(ref)
            end
          end)
        else
          vim.notify("No source buffer available for LSP context", vim.log.levels.WARN)
        end
      elseif choice.value == "project" then
        local item = ProjectContext.get_context()
        if item then
          local ref = Context.make_ref(item)
          Context.add(ref, item)
          insert_at_cursor(ref)
        end
      elseif choice.value == "file" then
        local ok, telescope = pcall(require, "telescope.builtin")
        if ok then
          telescope.find_files({
            attach_mappings = function(prompt_bufnr, map)
              local actions = require("telescope.actions")
              local action_state = require("telescope.actions.state")
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                  local filepath = selection.path or selection[1]
                  local file_content = vim.fn.readfile(filepath)
                  if file_content then
                    local item = {
                      type = "file",
                      name = vim.fn.fnamemodify(filepath, ":t"),
                      file = filepath,
                      content = table.concat(file_content, "\n"),
                    }
                    local ref = Context.make_ref(item)
                    Context.add(ref, item)
                    insert_at_cursor(ref)
                  end
                end
              end)
              return true
            end,
          })
        else
          vim.notify("Telescope not available for file picker", vim.log.levels.WARN)
        end
      elseif choice.value == "diff" then
        local diff = vim.fn.system("git diff")
        if diff and diff ~= "" and not diff:match("^fatal:") then
          local item = {
            type = "diff",
            name = "git diff",
            content = diff,
          }
          local ref = Context.make_ref(item)
          Context.add(ref, item)
          insert_at_cursor(ref)
        else
          vim.notify("No unstaged changes", vim.log.levels.INFO)
        end
      end
    end)
  end, { self.chat_input }, { "i" })

  -- close
  self:map(Config.options.chat.keymaps.close, function()
    self:hide()
    -- If current in insert mode, switch to insert mode
    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
  end, nil, { "n" })

  -- close_n
  if Config.options.chat.keymaps.close_n then
    self:map(Config.options.chat.keymaps.close_n, function()
      self:hide()
    end, nil, { "n" })
  end

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
  end, nil, { "n" })

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
  end, nil, { "n" })

  -- toggle sessions
  self:map(Config.options.chat.keymaps.toggle_sessions, function()
    local sessions_open = inTable(self.open_extra_panels, self.sessions_panel)
    if sessions_open then
      table.remove(self.open_extra_panels, sessions_open)
    else
      table.insert(self.open_extra_panels, self.sessions_panel)
    end
    self:redraw()
  end, nil, { "n" })

  -- new session
  self:map(Config.options.chat.keymaps.new_session, function()
    self:new_session()
    Sessions:refresh()
  end, { self.settings_panel, self.chat_input, self.help_panel }, { "n" })

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
  end, nil, { "n" })

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
  end, nil, { "n" })

  -- toggle role
  self:map(Config.options.chat.keymaps.toggle_message_role, function()
    self.role = self.role == ROLE_USER and ROLE_ASSISTANT or ROLE_USER
    self:render_role()
  end, nil, { "n" })

  -- draft message
  self:map(Config.options.chat.keymaps.draft_message, function()
    if self:isBusy() then
      vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(self.chat_input.bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")
    if #text > 0 then
      Utils.modify_buf(self.chat_input.bufnr, function(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
      end)
      self:add(self.role == ROLE_USER and QUESTION or ANSWER, text)
      if self.role ~= ROLE_USER then
        self.role = ROLE_USER
        self:render_role()
      end
    else
      vim.notify("Cannot add empty message.", vim.log.levels.WARN)
    end
  end, nil, { "n" })

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

  -- Initialize hints with default context (input panel)
  if self.hints_panel then
    self.active_panel = self.chat_input
    self:update_hints()
  end

  -- Setup resize handling
  local resize_group = vim.api.nvim_create_augroup("ChatGPTResize", { clear = true })
  local function on_resize()
    if self.layout and self.layout.winid then
      self:redraw(true)
    end
  end
  vim.api.nvim_create_autocmd("VimResized", { group = resize_group, callback = on_resize })
  -- WinResized available in Neovim 0.9+
  if vim.fn.has("nvim-0.9") == 1 then
    vim.api.nvim_create_autocmd("WinResized", { group = resize_group, callback = on_resize })
  end
  self.resize_group = resize_group

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
  -- Cleanup resize autocmd
  if self.resize_group then
    vim.api.nvim_create_augroup("ChatGPTResize", { clear = true })
  end
  self.layout:hide()
end

function Chat:show()
  -- Re-register resize handling
  local resize_group = vim.api.nvim_create_augroup("ChatGPTResize", { clear = true })
  local function on_resize()
    if self.layout and self.layout.winid then
      self:redraw(true)
    end
  end
  vim.api.nvim_create_autocmd("VimResized", { group = resize_group, callback = on_resize })
  if vim.fn.has("nvim-0.9") == 1 then
    vim.api.nvim_create_autocmd("WinResized", { group = resize_group, callback = on_resize })
  end
  self.resize_group = resize_group

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
