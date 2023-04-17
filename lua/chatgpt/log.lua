local M = {}
local Config = require("chatgpt.config")
local os = require("os")

local function open_log_file()
  local log_file = Config.options.log_file
  local log_file_handle, err = io.open(log_file, "a+")
  if not log_file_handle then
    print("Error opening log file: " .. log_file)
    print(err)
  end
  return log_file_handle
end

local function close_log_file(log_file_handle, log_file_handle_closed)
  if not log_file_handle_closed then
    log_file_handle:close()
  end
end

local function log_error(err, log_file)
  print("Error writing to log file: " .. log_file)
  print(err)
end

local function log_time()
  return os.date("%Y-%m-%d %H:%M:%S")
end

local function log_write(log_file_handle, str)
  local ok, err = log_file_handle:write(str)
  if not ok then
    log_error(err, log_file)
  end
end

local function log_writeln(log_file_handle, str)
  log_write(log_file_handle, str .. "\n")
end

local function log_writeln_json(log_file_handle, obj)
  local json_str = vim.json.encode(obj)
  log_writeln(log_file_handle, json_str)
end

local function log_writeln_json_pretty(log_file_handle, obj)
  local json_str = vim.json.encode(obj, { pretty = true })
  log_writeln(log_file_handle, json_str)
end

function M.log_write(log_func, ...)
  local log_file_handle = open_log_file()
  if not log_file_handle then
    return
  end
  log_file_handle_closed = false

  local log_msg = log_time() .. " - " .. log_func .. " - "
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    if type(arg) == "table" then
      arg = tostring(arg)
    end
    log_msg = log_msg .. arg
    if i ~= select("#", ...) then
      log_msg = log_msg .. ","
    end
  end

  log_writeln(log_file_handle, log_msg)
  close_log_file(log_file_handle, log_file_handle_closed)
end

function M.log_main(line)
  M.log_write("log_main", line)
end

local function log_edit(log_file_handle, input, instruction, output)
  log_writeln(log_file_handle, "Input: " .. (input or ""))
  log_writeln(log_file_handle, "Instruction: " .. (instruction or ""))
  log_writeln(log_file_handle, "Output: " .. (output or ""))
end

function M.log_edit(input, instruction, output, usage)
  local log_file_handle = open_log_file()
  if not log_file_handle then
    return
  end
  log_file_handle_closed = false

  M.log_write("log_main", "Code Edit:")
  log_edit(log_file_handle, input, instruction, output)

  close_log_file(log_file_handle, log_file_handle_closed)
end

function M.log_write_json(obj)
  local log_file_handle = open_log_file()
  if not log_file_handle then
    return
  end
  log_file_handle_closed = false

  log_writeln_json(log_file_handle, obj)
  close_log_file(log_file_handle, log_file_handle_closed)
end

return M
