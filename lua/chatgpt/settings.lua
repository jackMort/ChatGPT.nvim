local M = {}
M.vts = {}

local Popup = require("nui.popup")
local Config = require("chatgpt.config")

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

local float_validator = function(min, max)
  return function(value)
    return tonumber(value)
  end
end

local integer_validator = function(min, max)
  return function(value)
    return tonumber(value)
  end
end

local model_validator = function(value)
  return value
end

local params_order = { "model", "frequency_penalty", "presence_penalty", "max_tokens", "temperature", "top_p" }
local params_validators = {
  model = model_validator,
  frequency_penalty = float_validator(-2, 2),
  presence_penalty = float_validator(-2, 2),
  max_tokens = integer_validator(0, 4096),
  temperature = float_validator(0, 1),
  top_p = float_validator(0, 1),
}

local function write_virtual_text(bufnr, ns, line, chunks, mode)
  mode = mode or "extmark"
  if mode == "extmark" then
    return vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, { virt_text = chunks, virt_text_pos = "overlay" })
  elseif mode == "vt" then
    pcall(vim.api.nvim_buf_set_virtual_text, bufnr, ns, line, chunks, {})
  end
end

M.read_config = function()
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  local file = io.open(home .. "/" .. ".chatgpt-" .. M.type .. "-params.json", "rb")
  if not file then
    return nil
  end

  local jsonString = file:read("*a")
  file:close()

  return vim.json.decode(jsonString)
end

M.write_config = function(config)
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  local file, err = io.open(home .. "/" .. ".chatgpt-" .. M.type .. "-params.json", "w")
  if file ~= nil then
    local json_string = vim.json.encode(config)
    file:write(json_string)
    file:close()
  else
    vim.notify("Cannot save settings: " .. err, vim.log.levels.ERROR)
  end
end

M.get_settings_panel = function(type, default_params)
  M.type = type
  local custom_params = M.read_config()
  M.params = vim.tbl_deep_extend("force", {}, default_params, custom_params or {})

  M.panel = Popup(Config.options.settings_window)

  -- write details as virtual text
  local details = {}
  for _, key in pairs(params_order) do
    if M.params[key] ~= nil then
      local vt = {
        { Config.options.settings_window.setting_sign .. key .. ": ", "ErrorMsg" },
        { M.params[key] .. "", Config.options.highlights.params_value },
      }
      table.insert(details, vt)
    end
  end

  local line = 1
  local empty_lines = {}
  for _ = 1, #details do
    table.insert(empty_lines, "")
  end

  vim.api.nvim_buf_set_lines(M.panel.bufnr, line - 1, line - 1 + #empty_lines, false, empty_lines)
  for _, d in ipairs(details) do
    M.vts[line - 1] = write_virtual_text(M.panel.bufnr, namespace_id, line - 1, d)
    line = line + 1
  end

  M.panel:map("n", "<Enter>", function()
    local row, _ = unpack(vim.api.nvim_win_get_cursor(M.panel.winid))

    local existing_order = {}
    for _, key in ipairs(params_order) do
      if M.params[key] ~= nil then
        table.insert(existing_order, key)
      end
    end

    local key = existing_order[row]
    local value = M.params[key]
    M.open_edit_property_input(key, value, row, function(new_value)
      M.params[key] = params_validators[key](new_value)
      local vt = {

        { Config.options.settings_window.setting_sign .. key .. ": ", "ErrorMsg" },
        { M.params[key] .. "", "Identifier" },
      }
      vim.api.nvim_buf_del_extmark(M.panel.bufnr, namespace_id, M.vts[row - 1])
      M.vts[row - 1] = vim.api.nvim_buf_set_extmark(
        M.panel.bufnr,
        namespace_id,
        row - 1,
        0,
        { virt_text = vt, virt_text_pos = "overlay" }
      )
      M.write_config(M.params)
    end)
  end, {})

  return M.panel
end

M.open_edit_property_input = function(key, value, row, cb)
  local Input = require("nui.input")

  local input = Input({
    relative = {
      type = "win",
      winid = M.panel.winid,
    },
    position = {
      row = row - 1,
      col = 0,
    },
    size = {
      width = 38,
    },
    border = {
      style = "none",
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    prompt = Config.options.popup_input.prompt .. key .. ": ",
    default_value = "" .. value,
    on_submit = cb,
  })

  -- mount/open the component
  input:mount()
end

return M
