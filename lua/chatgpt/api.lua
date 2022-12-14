local job = require("plenary.job")
local Config = require("chatgpt.config")

local Api = {}

-- API URL
Api.URL = "https://api.openai.com/v1/completions"

-- API KEY
Api.OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not Api.OPENAI_API_KEY then
  error("OPENAI_API_KEY environment variable not set")
end

function Api.completions(prompt, cb)
  local params = vim.tbl_extend("keep", { prompt = prompt }, Config.options.openai_params)

  job
    :new({
      command = "curl",
      args = {
        Api.URL,
        "-H",
        "Content-Type: application/json",
        "-H",
        "Authorization: Bearer " .. Api.OPENAI_API_KEY,
        "-d",
        vim.fn.json_encode(params),
      },
      on_exit = vim.schedule_wrap(function(j, exit_code)
        if exit_code ~= 0 then
          -- TODO: better error handling
          vim.notify("An Error Occured, cannot fetch answer ...", vim.log.levels.ERROR)
          cb("ERROR: API Error")
        end

        local res = table.concat(j:result(), "\n")
        local json = vim.fn.json_decode(res)
        if json == nil then
          cb("No Response.")
        else
          local response = json.choices[1].text
          if type(response) == "string" and response ~= "" then
            cb(response)
          else
            cb("...")
          end
        end
      end),
    })
    :start()
end

return Api
