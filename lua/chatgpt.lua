-- main module file
local api = require("chatgpt.api")
local module = require("chatgpt.module")
local config = require("chatgpt.config")
local signs = require("chatgpt.signs")
local lsp_context = require("chatgpt.context.lsp")
local project_context = require("chatgpt.context.project")

local M = {}

M.setup = function(options)
  -- set custom highlights
  vim.api.nvim_set_hl(0, "ChatGPTQuestion", { fg = "#b4befe", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTWelcome", { fg = "#9399b2", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTTotalTokens", { fg = "#ffffff", bg = "#444444", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTotalTokensBorder", { fg = "#444444", default = true })

  vim.api.nvim_set_hl(0, "ChatGPTMessageAction", { fg = "#ffffff", bg = "#1d4c61", italic = true, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTCompletion", { fg = "#9399b2", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTContextRef", { fg = "#89b4fa", bg = "#1e1e2e", bold = true, default = true })

  vim.cmd("highlight default link ChatGPTSelectedMessage ColorColumn")

  config.setup(options)
  api.setup()
  signs.setup()
end

--
-- public methods for the plugin
--

M.openChat = function()
  module.open_chat()
end

M.selectAwesomePrompt = function()
  module.open_chat_with_awesome_prompt()
end

M.open_chat_with = function(opts)
  module.open_chat_with(opts)
end

M.edit_with_instructions = function()
  module.edit_with_instructions()
end

M.run_action = function(opts)
  module.run_action(opts)
end

M.complete_code = module.complete_code

-- Context APIs
M.add_context = function()
  lsp_context.add_context()
end

M.add_project_context = function()
  project_context.add_context()
end

return M
