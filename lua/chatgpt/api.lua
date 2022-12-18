local job = require("plenary.job")
local Config = require("chatgpt.config")

local Api = {}

-- API URL
Api.COMPLETIONS_URL = "https://api.openai.com/v1/completions"
Api.EDITS_URL = "https://api.openai.com/v1/edits"

-- API KEY
Api.OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not Api.OPENAI_API_KEY then
  error("OPENAI_API_KEY environment variable not set")
end

function Api.completions(prompt, cb)
  local params = vim.tbl_extend("keep", { prompt = prompt }, Config.options.openai_params)
  Api.make_call(Api.COMPLETIONS_URL, params, cb)
end

function Api.edits(input, instruction, cb)
  local params = vim.tbl_extend("keep", { input = input, instruction = instruction }, Config.options.openai_edit_params)
  Api.make_call(Api.EDITS_URL, params, cb)
end

function Api.make_call(url, params, cb)
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
        vim.fn.json_encode(params),
      },
      on_exit = vim.schedule_wrap(function(response, exit_code)
        Api.handle_response(response, exit_code, cb)
      end),
    })
    :start()
end

Api.handle_response = vim.schedule_wrap(function(response, exit_code, cb)
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
    local response = json.choices[1].text
    local total_tokens = json.usage.total_tokens
    if type(response) == "string" and response ~= "" then
      cb(response, total_tokens)
    else
      cb("...", total_tokens)
    end
  end
end)

function Api.close()
  if Api.job then
    job:shutdown()
  end
end

return Api
