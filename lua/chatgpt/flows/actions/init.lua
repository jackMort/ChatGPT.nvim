local M = {}

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
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
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
  local paths = {}

  -- add default actions
  local default_actions_path = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "actions.json"
  table.insert(paths, default_actions_path)
  for i = 1, #Config.options.actions_paths do
    paths[#paths + 1] = Config.options.actions_paths[i]
  end

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

  if item == nil then
    if action_name == nil then
      vim.notify("You need to specify an action", vim.log.levels.WARN)
    else
      vim.notify('Invalid input: "' .. action_name .. '"\n', vim.log.levels.WARN)
    end

    -- show the available valid actions
    local keys = {}
    for k, _ in pairs(ACTIONS) do
      table.insert(keys, k)
    end
    local s = table.concat(keys, ", ")

    vim.notify("Valid actions are: " .. s, vim.log.levels.WARN)

    return
  end

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

return M
