local Input = require("nui.input")

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

local ChatInput = Input:extend("SecretInput")

function ChatInput:init(popup_options, options)
  ChatInput.super.init(self, popup_options, options)

  self.input_props.on_submit = function(value)
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
end
return ChatInput
