local classes = require("chatgpt.common.classes")
local Path = require("plenary.path")
local scan = require("plenary.scandir")

local Session = classes.class()

local function parse_date_time(str)
  local year, month, day, hour, min, sec = string.match(str, "(%d+)-(%d+)-(%d+)_(%d+):(%d+):(%d+)")
  return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
end

function Session:init(opts)
  opts = opts or {}
  self.filename = opts.filename or nil
  if self.filename then
    self:load()
  else
    self.name = opts.name or os.date("%Y-%m-%d_%H:%M:%S")
    self.filename = Session.get_dir():joinpath(self.name .. ".json"):absolute()
    self.conversation = {}
    self.settings = {}
  end
end

function Session:to_export()
  return {
    name = self.name,
    settings = self.settings,
    conversation = self.conversation,
  }
end

function Session:add_item(item)
  table.insert(self.conversation, item)
  self:save()
end

function Session:save()
  local data = self:to_export()

  local file, err = io.open(self.filename, "w")
  if file ~= nil then
    local json_string = vim.json.encode(data)
    file:write(json_string)
    file:close()
  else
    vim.notify("Cannot save session: " .. err, vim.log.levels.ERROR)
  end
end

function Session:load()
  local file = io.open(self.filename, "rb")
  if not file then
    vim.notify("Cannot read session file", vim.log.levels.ERROR)
    return nil
  end

  local jsonString = file:read("*a")
  file:close()

  local data = vim.json.decode(jsonString)
  self.name = data.name
  self.settings = data.settings
  self.conversation = data.conversation
end

--
-- static methods
--

function Session.get_dir()
  local dir = Path:new(vim.fn.stdpath("state")):joinpath("chatgpt")
  if not dir:exists() then
    dir:mkdir()
  end
  return dir
end

function Session.list_sessions()
  local dir = Session.get_dir()
  local files = scan.scan_dir(dir:absolute(), { hidden = false })
  local sessions = {}

  for _, filename in pairs(files) do
    local ts = parse_date_time(filename)
    local name = os.date("%c", ts)
    table.insert(sessions, {
      filename = filename,
      name = name,
      ts = ts,
    })
  end

  table.sort(sessions, function(a, b)
    return a.ts > b.ts
  end)

  return sessions
end

function Session.latest()
  local sessions = Session.list_sessions()
  if #sessions > 0 then
    local session = sessions[1]
    return Session.new({ filename = session.filename })
  end
  return Session.new()
end

return Session
