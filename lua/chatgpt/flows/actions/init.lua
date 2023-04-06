local M = {}

-- CUSTOM_CODE_ACTION = [[
-- I have the following code:
-- ```{{filetype}}
-- {{input}}
-- ```
-- {{instruction}}:
-- ```
-- ]]

local ChatAction = require("chatgpt.flows.actions.chat")
local CompletionAction = require("chatgpt.flows.actions.completions")
local EditAction = require("chatgpt.flows.actions.edits")
local Config = require("chatgpt.config")

local classes_by_type = {
  chat = ChatAction,
  completion = CompletionAction,
  edit = EditAction,
}

local read_actions_from_file = function(filename)
  local home = os.getenv("HOME")
  filename = filename:gsub("~", home)
  local file = io.open(filename, "rb")
  if not file then
    vim.notify("Cannot read action file: " .. filename, vim.log.levels.ERROR)
    return nil
  end

  local json_string = file:read("*a")
  file:close()

  return vim.json.decode(json_string)
end

function M.read_actions()
  local actions = {}

  -- add default actions
  local paths = Config.options.actions_paths
  local default_actions_path = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "actions.json"
  table.insert(paths, default_actions_path)

  for _, filename in ipairs(paths) do
    local data = read_actions_from_file(filename)
    if data then
      for action_name, action_definition in pairs(data) do
        actions[action_name] = action_definition
      end
    end
  end
  return actions
end

function M.run_action(opts)
  local ACTIONS = M.read_actions()

  local action_name = opts.fargs[1]
  local item = ACTIONS[action_name]

  -- parse args
  --
  if item.args then
    item.opts.variables = {}
    local i = 2
    for key, value in pairs(item.args) do
      local arg = opts.fargs[i]
      -- TODO: validataion
      item.opts.variables[key] = arg or value.default or ""
      i = i + 1
    end
  end

  opts = vim.tbl_extend("force", {}, opts, item.opts)
  local class = classes_by_type[item.type]
  local action = class.new(opts)
  action:run()
end

-- function M.run_custom_code_action(opts)
--   local Input = require("nui.input")

--   local input = Input({
--     position = "50%",
--     size = {
--       width = 60,
--     },
--     border = {
--       style = "rounded",
--       text = {
--         top = " Custom Code Action ",
--         top_align = "center",
--       },
--     },
--     win_options = {
--       winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
--     },
--   }, {
--     prompt = Config.options.chat_input.prompt,
--     on_submit = function(value)
--       opts = vim.tbl_extend("force", {}, opts, {
--         template = CUSTOM_CODE_ACTION,
--         params = {
--           model = "code-davinci-002",
--           stop = { "```" },
--         },
--         variables = {
--           instruction = value,
--         },
--       })
--       local action = CompletionAction.new(opts)
--       action:run()
--     end,
--   })

--   local close_keymaps = Config.options.keymaps.close
--   if type(close_keymaps) ~= "table" then
--     close_keymaps = { close_keymaps }
--   end

--   for _, keymap in ipairs(close_keymaps) do
--     input:map("i", keymap, function()
--       input.input_props.on_close()
--     end, { noremap = true, silent = true })
--   end

--   input:mount()
-- end

return M
