local job = require("plenary.job")

local Api = {}

Api.BASE_URL = "https://api.openai.com/v1/completions"

Api.OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
if not Api.OPENAI_API_KEY then
	error("OPENAI_API_KEY environment variable not set")
end

function Api.completions(prompt, cb)
	local body = {
		prompt = prompt,
		model = "text-davinci-003",
		temperature = 0,
		max_tokens = 300,
		n = 1,
		top_p = 1,
		frequency_penalty = 0,
		presence_penalty = 0,
	}

	local json_body = vim.fn.json_encode(body)
	job:new({
		command = "curl",
		args = {
			Api.BASE_URL,
			"-H",
			"Content-Type: application/json",
			"-H",
			"Authorization: Bearer " .. Api.OPENAI_API_KEY,
			"-d",
			json_body,
		},
		on_exit = vim.schedule_wrap(function(j, exit_code)
			local res = table.concat(j:result(), "\n")
			if exit_code ~= 0 then
				-- TODO: better error handling
				vim.notify("An Error Occured, cannot fetch answer ...", vim.log.levels.ERROR)
				cb("ERROR: API Error")
			end

			local json = vim.fn.json_decode(res)
			-- TODO: handle possible errors
			cb(json.choices[1].text)
		end),
	}):start()
end

return Api
