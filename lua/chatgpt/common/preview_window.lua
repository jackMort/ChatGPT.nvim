local Popup = require("nui.popup")
local Config = require("chatgpt.config")

local PreviewWindow = Popup:extend("PreviewWindow")

function PreviewWindow:init(options)
  options = vim.tbl_deep_extend("keep", options or {}, {
    position = 1,
    size = {
      width = "40%",
      height = 10,
    },
    padding = { 1, 1, 1, 1 },
    enter = true,
    focusable = true,
    zindex = 50,
    border = {
      style = "rounded",
    },
    buf_options = {
      modifiable = false,
      readonly = true,
      filetype = "markdown",
    },
    win_options = {
      wrap = true,
      linebreak = true,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  })

  PreviewWindow.super.init(self, options)
end

function PreviewWindow:mount()
  PreviewWindow.super.mount(self)

  -- close
  local keys = Config.options.chat.keymaps.close
  if type(keys) ~= "table" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    self:map("n", key, function()
      self:unmount()
    end)
  end
end

return PreviewWindow
