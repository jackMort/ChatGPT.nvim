-- main module file
local module = require("chatgpt.module")
local config = require("chatgpt.config")
local signs = require("chatgpt.signs")

local M = {}

M.setup = function(options)
  -- set custom highlights
  vim.api.nvim_set_hl(0, "ChatGPTQuestion", { fg = "#b4befe", italic = true, bold = false, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTWelcome", { fg = "#9399b2", italic = true, bold = false, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTotalTokens", { fg = "#ffffff", bg = "#444444", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTotalTokensBorder", { fg = "#444444", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTCompletion", { fg = "#9399b2", italic = true, bold = false, default = true })

  config.setup(options)
  signs.setup()
end

--
-- public methods for the plugin
--

M.openChat = function()
  module.openChat()
end

M.selectAwesomePrompt = function()
  module.open_chat_with_awesome_prompt()
end

M.edit_with_instructions = function()
  module.edit_with_instructions()
end

M.run_action = function(opts)
  module.run_action(opts)
end

M.run_custom_code_action = function(opts)
  module.run_custom_code_action(opts)
end

M.complete_code = module.complete_code

return M
