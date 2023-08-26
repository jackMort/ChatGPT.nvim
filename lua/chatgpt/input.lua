local Popup = require("nui.popup")
local Text = require("nui.text")
local defaults = require("nui.utils").defaults
local is_type = require("nui.utils").is_type
local event = require("nui.utils.autocmd").event
local Config = require("chatgpt.config")

-- exiting insert mode places cursor one character backward,
-- so patch the cursor position to one character forward
-- when unmounting input.
---@param target_cursor number[]
---@param force? boolean
local function patch_cursor_position(target_cursor, force)
  local cursor = vim.api.nvim_win_get_cursor(0)

  if target_cursor[2] == cursor[2] and force then
    -- didn't exit insert mode yet, but it's gonna
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + 1 })
  elseif target_cursor[2] - 1 == cursor[2] then
    -- already exited insert mode
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] + 1 })
  end
end

local Input = Popup:extend("NuiInput")

---@param popup_options table
---@param options table
function Input:init(popup_options, options)
  vim.fn.sign_define("multiprompt_sign", { text = " ", texthl = "LineNr", numhl = "LineNr" })
  vim.fn.sign_define("singleprompt_sign", { text = " ", texthl = "LineNr", numhl = "LineNr" })

  popup_options.enter = true

  popup_options.buf_options = defaults(popup_options.buf_options, {})

  if not is_type("table", popup_options.size) then
    popup_options.size = {
      width = popup_options.size,
    }
  end

  popup_options.size.height = 2

  Input.super.init(self, popup_options)

  self._.default_value = defaults(options.default_value, "")
  self._.prompt = Text(defaults(options.prompt, ""))
  self._.disable_cursor_position_patch = defaults(options.disable_cursor_position_patch, false)

  local props = {}

  self.input_props = props

  props.on_submit = function(value)
    local target_cursor = vim.api.nvim_win_get_cursor(self._.position.win)

    local prompt_normal_mode = vim.fn.mode() == "n"

    vim.schedule(function()
      if prompt_normal_mode then
        -- NOTE: on prompt-buffer normal mode <CR> causes neovim to enter insert mode.
        --  ref: https://github.com/neovim/neovim/blob/d8f5f4d09078/src/nvim/normal.c#L5327-L5333
        vim.api.nvim_command("stopinsert")
      end

      if not self._.disable_cursor_position_patch then
        patch_cursor_position(target_cursor, prompt_normal_mode)
      end

      if options.on_submit then
        options.on_submit(value)
      end
    end)
  end

  props.on_close = function()
    local target_cursor = vim.api.nvim_win_get_cursor(self._.position.win)

    self:unmount()

    vim.schedule(function()
      if vim.fn.mode() == "i" then
        vim.api.nvim_command("stopinsert")
      end

      if not self._.disable_cursor_position_patch then
        patch_cursor_position(target_cursor)
      end

      if options.on_close then
        options.on_close()
      end
    end)
  end

  if options.on_change then
    props.on_change = function()
      local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
      local max_lines = Config.options.popup_input.max_visible_lines -- Set the maximum number of lines here
      if max_lines ~= nil and #lines > max_lines then
        lines = { unpack(lines, 1, max_lines) } -- Only keep the first max_lines lines
      end
      if #lines == 1 then
        vim.fn.sign_place(0, "my_group", "singleprompt_sign", self.bufnr, { lnum = 1, priority = 10 })
      else
        for i = 1, #lines do
          vim.fn.sign_place(0, "my_group", "multiprompt_sign", self.bufnr, { lnum = i, priority = 10 })
        end
      end
      options.on_change(lines)
    end
  end
end

function Input:mount()
  local props = self.input_props

  Input.super.mount(self)

  vim.api.nvim_buf_set_option(0, "ft", "chatgpt-input")

  if props.on_change then
    vim.api.nvim_buf_attach(self.bufnr, false, {
      on_lines = props.on_change,
    })
  end

  if #self._.default_value then
    self:on(event.InsertEnter, function()
      vim.api.nvim_feedkeys(self._.default_value, "n", false)
    end, { once = true })
  end

  self:map("i", Config.options.popup_input.submit, function()
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    local value = table.concat(lines, "\n")
    props.on_submit(value)
  end, { noremap = true })

  self:map("n", Config.options.popup_input.submit_n, function()
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    local value = table.concat(lines, "\n")
    props.on_submit(value)
  end, { noremap = true })

  vim.api.nvim_command("startinsert!")
  vim.fn.sign_place(0, "my_group", "singleprompt_sign", self.bufnr, { lnum = 1, priority = 10 })
end

local NuiInput = Input

return NuiInput
