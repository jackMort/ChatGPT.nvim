local job = require("plenary.job")
local Config = require("chatgpt.config")
local logger = require("chatgpt.common.logger")

local Api = {}

-- API URL
Api.COMPLETIONS_URL = "https://api.openai.com/v1/completions"
Api.CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions"
Api.EDITS_URL = "https://api.openai.com/v1/edits"

function Api.completions(custom_params, cb)
  local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
  Api.make_call(Api.COMPLETIONS_URL, params, cb)
end

function Api.chat_completions(custom_params, cb)
  local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
  local stream = params.stream or false
  if stream then
    local raw_chunks = ""
    local state = "START"

    cb = vim.schedule_wrap(cb)

    Api.exec("curl", {
      "--silent",
      "--show-error",
      "--no-buffer",
      Api.CHAT_COMPLETIONS_URL,
      "-H",
      "Content-Type: application/json",
      "-H",
      "Authorization: Bearer " .. Api.OPENAI_API_KEY,
      "-d",
      vim.json.encode(params),
    }, function(chunk)
      local ok, json = pcall(vim.json.decode, chunk)
      if ok and json ~= nil then
        if json.error ~= nil then
          cb(json.error.message, "ERROR")
          return
        end
      end
      for line in chunk:gmatch("[^\n]+") do
        local raw_json = string.gsub(line, "^data: ", "")
        if raw_json == "[DONE]" then
          cb(raw_chunks, "END")
        else
          ok, json = pcall(vim.json.decode, raw_json)
          if ok and json ~= nil then
            if
              json
              and json.choices
              and json.choices[1]
              and json.choices[1].delta
              and json.choices[1].delta.content
            then
              cb(json.choices[1].delta.content, state)
              raw_chunks = raw_chunks .. json.choices[1].delta.content
              state = "CONTINUE"
            end
          end
        end
      end
    end, function(err, _)
      cb(err, "ERROR")
    end)
  else
    Api.make_call(Api.CHAT_COMPLETIONS_URL, params, cb)
  end
end

function Api.edits(custom_params, cb)
  local params = vim.tbl_extend("keep", custom_params, Config.options.openai_edit_params)
  if params.model == "text-davinci-edit-001" or params.model == "code-davinci-edit-001" then
    vim.notify("Edit models are deprecated", vim.log.levels.WARN)
    Api.make_call(Api.EDITS_URL, params, cb)
    return
  end

  Api.make_call(Api.CHAT_COMPLETIONS_URL, params, cb)
end

function Api.make_call(url, params, cb)
  TMP_MSG_FILENAME = os.tmpname()
  local f = io.open(TMP_MSG_FILENAME, "w+")
  if f == nil then
    vim.notify("Cannot open temporary message file: " .. TMP_MSG_FILENAME, vim.log.levels.ERROR)
    return
  end
  f:write(vim.fn.json_encode(params))
  f:close()
  Api.job = job
    :new({
      command = "curl",
      args = {
        url,
        "-H",
        "Content-Type: application/json",
        "-H",
        "Authorization: Bearer " .. Api.OPENAI_API_KEY,
        "-d",
        "@" .. TMP_MSG_FILENAME,
      },
      on_exit = vim.schedule_wrap(function(response, exit_code)
        Api.handle_response(response, exit_code, cb)
      end),
    })
    :start()
end

Api.handle_response = vim.schedule_wrap(function(response, exit_code, cb)
  os.remove(TMP_MSG_FILENAME)
  if exit_code ~= 0 then
    vim.notify("An Error Occurred ...", vim.log.levels.ERROR)
    cb("ERROR: API Error")
  end

  local result = table.concat(response:result(), "\n")
  local json = vim.fn.json_decode(result)
  if json == nil then
    cb("No Response.")
  elseif json.error then
    cb("// API ERROR: " .. json.error.message)
  else
    local message = json.choices[1].message
    if message ~= nil then
      local message_response
      local first_message = json.choices[1].message
      if first_message.function_call then
        message_response = vim.fn.json_decode(first_message.function_call.arguments)
      else
        message_response = first_message.content
      end
      if (type(message_response) == "string" and message_response ~= "") or type(message_response) == "table" then
        cb(message_response, json.usage)
      else
        cb("...")
      end
    else
      local response_text = json.choices[1].text
      if type(response_text) == "string" and response_text ~= "" then
        cb(response_text, json.usage)
      else
        cb("...")
      end
    end
  end
end)

function Api.close()
  if Api.job then
    job:shutdown()
  end
end

local splitCommandIntoTable = function(command)
  local cmd = {}
  for word in command:gmatch("%S+") do
    table.insert(cmd, word)
  end
  return cmd
end

local loadApiKey = function(command)
  local cmd = splitCommandIntoTable(command)
  -- API KEY
  job
    :new({
      command = cmd[1],
      args = vim.list_slice(cmd, 2, #cmd),
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          logger.warn("Config 'api_key_cmd' did not return a value when executed")
          return
        end
        Api.OPENAI_API_KEY = j:result()[1]:gsub("%s+$", "")
      end,
    })
    :start()
end

function Api.setup()
  Api.OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
  if not Api.OPENAI_API_KEY then
    if Config.options.api_key_cmd ~= nil and Config.options.api_key_cmd ~= "" then
      loadApiKey(Config.options.api_key_cmd)
    else
      logger.warn("OPENAI_API_KEY environment variable not set")
      return
    end
  end
  if Api.OPENAI_API_KEY ~= nil and Api.OPENAI_API_KEY ~= "" then
    Api.OPENAI_API_KEY = Api.OPENAI_API_KEY:gsub("%s+$", "")
  end
end

function Api.exec(cmd, args, on_stdout_chunk, on_complete)
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local stderr_chunks = {}

  local function on_stdout_read(_, chunk)
    if chunk then
      vim.schedule(function()
        on_stdout_chunk(chunk)
      end)
    end
  end

  local function on_stderr_read(_, chunk)
    if chunk then
      table.insert(stderr_chunks, chunk)
    end
  end

  local handle, err
  handle, err = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    if handle ~= nil then
      handle:close()
    end

    vim.schedule(function()
      if code ~= 0 then
        on_complete(vim.trim(table.concat(stderr_chunks, "")))
      end
    end)
  end)

  if not handle then
    on_complete(cmd .. " could not be started: " .. err)
  else
    stdout:read_start(on_stdout_read)
    stderr:read_start(on_stderr_read)
  end
end

return Api
