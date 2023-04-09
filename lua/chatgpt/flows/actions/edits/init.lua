local classes = require("chatgpt.common.classes")
local BaseAction = require("chatgpt.flows.actions.base")
local Api = require("chatgpt.api")
local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

-- curl https://api.openai.com/v1/edits \
--   -H "Content-Type: application/json" \
--   -H "Authorization: Bearer $OPENAI_API_KEY" \
--   -d '{
--   "model": "text-davinci-edit-001",
--   "input": "```r\ngenerate_random_points = function( base_lon, base_lat=38, max_distance = 10000, n_points=10, sample_method='hardcore',\n                                  random_seed = floor( base_lon * base_lat * 10000)) {\n\n  # for random point in the area -1...1, want to find latitude and longitude that matches these random points\n  # base_lat + random *\n\n set.seed(random_seed)\n\n lat_factor = max_distance / m_per_lat()\n lon_factor = max_distance / m_per_lon( base_lat )\n\n if (sample_method=='hardcore') {\n  beta <- n_points * 2; R = n_points / 2000\n  win <- disc(1) # Unit square for simulation\n  X1 <- rHardcore(beta, R, W = win) # Exact sampling -- beware it may run forever for some par.!\n } else {\n   # use random sampler\n }\n\nX1 %>%\n  as_tibble() %>%\n  mutate(\n         target_lon = base_lon + (x * lon_factor),\n         target_lat = base_lat + (y * lat_factor),\n         dist = distance_from( base_lon, base_lat, target_lon, target_lat)\n  ) %>%\n  filter( dist < max_distance) %>%\n  mutate(random=runif(n())) %>%\n  arrange(random) %>%\n  select(-random)\n\n}\n```\n",
--   "instruction": "Insert a roxygen skeleton to document this R function:",
--   "temperature": 0.7,
--   "top_p": 1
-- }'

local EditAction = classes.class(BaseAction)

local STRATEGY_REPLACE = "replace"
local STRATEGY_DISPLAY = "display"

function EditAction:init(opts)
  self.super:init(opts)
  self.params = opts.params or {}
  self.template = opts.template or "{{input}}"
  self.variables = opts.variables or {}
  self.strategy = opts.strategy or STRATEGY_REPLACE
end

function EditAction:render_template()
  local data = {
    filetype = self:get_filetype(),
    input = self:get_selected_text(),
  }
  data = vim.tbl_extend("force", {}, data, self.variables)
  local result = self.template
  for key, value in pairs(data) do
    result = result:gsub("{{" .. key .. "}}", value)
  end
  return result
end

function EditAction:get_params()
  return vim.tbl_extend("force", Config.options.openai_edit_params, self.params, { input = self:render_template() })
end

function EditAction:run()
  vim.schedule(function()
    self:set_loading(true)

    local params = self:get_params()
    Api.edits(params, function(answer, usage)
      self:on_result(answer, usage)
    end)
  end)
end

function EditAction:on_result(answer, usage)
  vim.schedule(function()
    self:set_loading(false)

    local bufnr = self:get_bufnr()
    local visual_lines, start_row, start_col, end_row, end_col = self:get_visual_selection(bufnr)
    local nlcount = Utils.count_newlines_at_end(table.concat(visual_lines, "\n"))
    local answer_nlfixed = Utils.replace_newlines_at_end(answer, nlcount)
    local lines = Utils.split_string_by_line(answer_nlfixed)
    vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
  end)
end

return EditAction
