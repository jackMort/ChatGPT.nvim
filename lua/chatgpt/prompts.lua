local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local job = require("plenary.job")

local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")

local function defaulter(f, default_opts)
  default_opts = default_opts or {}
  return {
    new = function(opts)
      if conf.preview == false and not opts.preview then
        return false
      end
      opts.preview = type(opts.preview) ~= "table" and {} or opts.preview
      if type(conf.preview) == "table" then
        for k, v in pairs(conf.preview) do
          opts.preview[k] = vim.F.if_nil(opts.preview[k], v)
        end
      end
      return f(opts)
    end,
    __call = function()
      local ok, err = pcall(f(default_opts))
      if not ok then
        error(debug.traceback(err))
      end
    end,
  }
end

local display_content_wrapped = defaulter(function(_)
  return previewers.new_buffer_previewer({
    define_preview = function(self, entry, status)
      local width = vim.api.nvim_win_get_width(self.state.winid)
      entry.preview_command(entry, self.state.bufnr, width)
    end,
  })
end, {})

local function preview_command(entry, bufnr, width)
  vim.api.nvim_buf_call(bufnr, function()
    local preview = Utils.wrapTextToTable(entry.value, width - 5)
    table.insert(preview, 1, "---")
    table.insert(preview, 1, entry.display)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, preview)
  end)
end

local function entry_maker(entry)
  return {
    value = entry.prompt,
    display = entry.act,
    ordinal = entry.act,
    preview_command = preview_command,
  }
end

local finder = function(opts)
  local job_started = false
  local job_completed = false
  local results = {}
  local num_results = 0

  return setmetatable({
    close = function()
      -- TODO: check if we need to make some cleanup
    end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      if job_completed then
        local current_count = num_results
        for index = 1, current_count do
          if process_result(results[index]) then
            break
          end
        end
        process_complete()
      end

      if not job_started then
        job_started = true
        job
          :new({
            command = "curl",
            args = {
              opts.url,
            },
            on_exit = vim.schedule_wrap(function(j, exit_code)
              if exit_code ~= 0 then
                vim.notify("An Error Occurred, cannot fetch list of prompts ...", vim.log.levels.ERROR)
                process_complete()
              end

              local response = table.concat(j:result(), "\n")
              local lines = {}
              for line in string.gmatch(response, "[^\n]+") do
                local act, _prompt = string.match(line, '"(.*)","(.*)"')
                if act ~= "act" and act ~= nil then
                  _prompt = string.gsub(_prompt, '""', '"')
                  table.insert(lines, { act = act, prompt = _prompt })
                end
              end

              for _, line in ipairs(lines) do
                local v = entry_maker(line)
                num_results = num_results + 1
                results[num_results] = v
                process_result(v)
              end

              process_complete()
              job_completed = true
            end),
          })
          :start()
      end
    end,
  })
end
--

local M = {}
function M.selectAwesomePrompt(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "ChatGPT Acts As ...",
      prompt_prefix = Config.options.popup_input.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Prompt",
      finder = finder({ url = Config.options.predefined_chat_gpt_prompts }),
      sorter = conf.generic_sorter(opts),
      previewer = display_content_wrapped.new({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          opts.cb(selection.display, selection.value)
        end)
        return true
      end,
    })
    :find()
end

return M
