local Popup = require("nui.popup")
local Config = require("chatgpt.config")

local SystemWindow = Popup:extend("SystemWindow")

function SystemWindow:init(options)
  self.working = false
  self.on_change = options.on_change

  options = vim.tbl_deep_extend("force", options or {}, Config.options.system_window)

  SystemWindow.super.init(self, options)
end

function SystemWindow:toggle_placeholder()
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")

  if self.extmark then
    vim.api.nvim_buf_del_extmark(self.bufnr, Config.namespace_id, self.extmark)
  end

  if #text == 0 then
    self.extmark = vim.api.nvim_buf_set_extmark(self.bufnr, Config.namespace_id, 0, 0, {
      virt_text = {
        {
          "You are a helpful assistant.",
          "@comment",
        },
      },
      virt_text_pos = "overlay",
    })
  end
end

function SystemWindow:set_text(text)
  self.working = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, text)
  self.working = false
end

function SystemWindow:mount()
  SystemWindow.super.mount(self)

  self:toggle_placeholder()
  vim.api.nvim_buf_attach(self.bufnr, false, {
    on_lines = function()
      self:toggle_placeholder()

      if not self.working then
        local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
        local text = table.concat(lines, "\n")
        self.on_change(text)
      end
    end,
  })
end

return SystemWindow
