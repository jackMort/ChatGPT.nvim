local Config = require("chatgpt.config")
local Utils = require("chatgpt.utils")

local Chat = {}
Chat.__index = Chat

QUESTION, ANSWER = 1, 2

function Chat:new(bufnr, winid)
  self = setmetatable({}, Chat)

  self.bufnr = bufnr
  self.winid = winid
  self.selectedIndex = 0
  self.messages = {}
  self.timer = nil
  self.total_tokens = 0

  return self
end

function Chat:close()
  self:stopTimer()
end

function Chat:welcome()
  local lines = {}
  local end_line = 0
  for line in string.gmatch(Config.options.welcome_message, "[^\n]+") do
    table.insert(lines, line)
    end_line = end_line + 1
  end

  self:set_lines(0, 0, false, lines)
  for line_num = 0, end_line do
    self:add_highlight("Comment", line_num, 0, -1)
  end
end

function Chat:isBusy()
  return self.timer ~= nil
end

function Chat:add(type, text, total_tokens)
  if not self:is_buf_exists() then
    return
  end

  if total_tokens ~= nil then
    self.total_tokens = self.total_tokens + total_tokens
  end

  local width = self:get_width() - 10 -- add some space
  local max_width = Config.options.max_line_length
  if width > max_width then
    max_width = width
  end
  text = Utils.wrapText(text, width)

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
    type = type,
    text = text,
    lines = lines,
    nr_of_lines = nr_of_lines,
    start_line = start_line,
    end_line = start_line + nr_of_lines - 1,
    tokens = total_tokens,
  })
  self:next()
  self:renderLastMessage()
end

function Chat:addQuestion(text)
  self:add(QUESTION, text)
end

function Chat:addAnswer(text, total_tokens)
  self:add(ANSWER, text, total_tokens)
end

function Chat:next()
  local count = self:count()
  if self.selectedIndex < count then
    self.selectedIndex = self.selectedIndex + 1
  else
    self.selectedIndex = 1
  end
end

function Chat:getSelected()
  return self.messages[self.selectedIndex]
end

function Chat:renderLastMessage()
  local isTimerSet = self.timer ~= nil
  self:stopTimer()

  local signs = { Config.options.question_sign, Config.options.answer_sign }
  local msg = self:getSelected()

  local lines = {}
  local i = 0
  for w in string.gmatch(msg.text, "[^\r\n]+") do
    local prefix = "   │ "
    if i == 0 then
      prefix = " " .. signs[msg.type] .. " │ "

      if Config.options.show_total_token_spend and msg.type == ANSWER then
        prefix = prefix .. string.format("[%d] ", msg.tokens)
      end
    end
    table.insert(lines, prefix .. w)
    i = i + 1
  end
  table.insert(lines, "")

  local startIdx = self.selectedIndex == 1 and 0 or -1
  if isTimerSet then
    startIdx = startIdx - 1
  end
  self:set_lines(startIdx, -1, false, lines)

  if msg.type == QUESTION then
    for index, _ in ipairs(lines) do
      self:add_highlight("Comment", msg.start_line + index - 1, 0, -1)
    end
  end

  if self.selectedIndex > 2 then
    self:set_cursor({ msg.end_line - 1, 0 })
  end
end

function Chat:showProgess()
  local idx = 1
  local chars = { "|", "/", "-", "\\" }
  self.timer = vim.loop.new_timer()
  self.timer:start(
    0,
    250,
    vim.schedule_wrap(function()
      local char = chars[idx]
      self:set_lines(
        -2,
        -1,
        false,
        { "   " .. char .. " " .. Config.options.loading_text .. " " .. string.rep(".", idx - 1) }
      )
      if idx < 4 then
        idx = idx + 1
      else
        idx = 1
      end
    end)
  )
end

function Chat:stopTimer()
  if self.timer ~= nil then
    self.timer:stop()
    self.timer = nil
  end
end

function Chat:toString()
  local str = ""
  for _, msg in pairs(self.messages) do
    str = str .. msg.text .. "\n"
  end
  return str
end

function Chat:count()
  local count = 0
  for _ in pairs(self.messages) do
    count = count + 1
  end
  return count
end

function Chat:is_buf_exists()
  return vim.fn.bufexists(self.bufnr) == 1
end

function Chat:set_lines(start_idx, end_idx, strict_indexing, lines)
  if self:is_buf_exists() then
    vim.api.nvim_buf_set_option(self.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(self.bufnr, start_idx, end_idx, strict_indexing, lines)
    vim.api.nvim_buf_set_option(self.bufnr, "modifiable", false)
  end
end

function Chat:add_highlight(hl_group, line, col_start, col_end)
  if self:is_buf_exists() then
    vim.api.nvim_buf_add_highlight(self.bufnr, -1, hl_group, line, col_start, col_end)
  end
end

function Chat:set_cursor(pos)
  if self:is_buf_exists() then
    vim.api.nvim_win_set_cursor(self.winid, pos)
  end
end

function Chat:get_width()
  if self:is_buf_exists() then
    return vim.api.nvim_win_get_width(self.winid)
  end
end

return Chat
