local Chat = {}
Chat.__index = Chat

QUERY = 1
ANSWER = 2
SIGNS = { "", "" }

function Chat:new(bufnr, winid)
  self = setmetatable({}, Chat)

  self.bufnr = bufnr
  self.winid = winid
  self.selectedIndex = 0
  self.messages = {}
  self.timer = nil

  return self
end

function Chat:isBusy()
  return self.timer ~= nil
end

function Chat:add(type, text)
  local start_line = 0
  if self.selectedIndex > 0 then
    local prev = self.messages[self.selectedIndex]
    start_line = prev.end_line + (prev.type == ANSWER and 2 or 1)
  end

  local lines = {}
  local nr_of_lines = 0
  for line in string.gmatch(text, "[^\r\n]+") do
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
  })
  self:next()
end

function Chat:addQuery(text)
  self:add(QUERY, text)
end

function Chat:addAnswer(text)
  self:add(ANSWER, text)
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

  local msg = self:getSelected()
  local lines = {}
  local i = 0
  for w in string.gmatch(msg.text, "[^\r\n]+") do
    local prefix = "   │ "
    if i == 0 then
      prefix = " " .. SIGNS[msg.type] .. " │ "
    end
    table.insert(lines, prefix .. w)
    i = i + 1
  end
  table.insert(lines, "")

  local startIdx = self.selectedIndex == 1 and 0 or -1
  if isTimerSet then
    startIdx = startIdx - 1
  end
  vim.api.nvim_buf_set_lines(self.bufnr, startIdx, -1, false, lines)

  if msg.type == QUERY then
    vim.api.nvim_buf_add_highlight(self.bufnr, 0, "Comment", msg.start_line, 0, -1)
  end

  if self.selectedIndex > 1 then
    vim.api.nvim_win_set_cursor(self.winid, { msg.end_line - 1, 0 })
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
      vim.api.nvim_buf_set_lines(
        self.bufnr,
        -2,
        -1,
        false,
        { "   " .. char .. " loading " .. string.rep(".", idx - 1) }
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

return Chat
