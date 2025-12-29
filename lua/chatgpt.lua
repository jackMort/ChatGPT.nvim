-- main module file
local api = require("chatgpt.api")
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

  vim.api.nvim_set_hl(0, "ChatGPTTokens", { fg = "#cdd6f4", bg = "#313244", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTokensBorder", { fg = "#313244", default = true })

  vim.api.nvim_set_hl(0, "ChatGPTMessageAction", { fg = "#ffffff", bg = "#1d4c61", italic = true, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTCompletion", { fg = "#9399b2", italic = true, bold = false, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTContextRef", { fg = "#89b4fa", bg = "#1e1e2e", bold = true, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTInlineCode", { fg = "#f38ba8", bg = "#1e1e2e", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTCodeBlock", { bg = "#181825", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTCodeBlockHeader", { fg = "#6c7086", bg = "#181825", italic = true, default = true })

  vim.api.nvim_set_hl(0, "ChatGPTLink", { fg = "#89b4fa", underline = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTBold", { bold = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTItalic", { italic = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTHeader", { fg = "#cba6f7", bold = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTDivider", { fg = "#313244", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTListMarker", { fg = "#f9e2af", bold = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTBlockquote", { fg = "#a6adc8", italic = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTHRule", { fg = "#45475a", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTaskDone", { fg = "#a6e3a1", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTTaskPending", { fg = "#f9e2af", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTStrikethrough", { strikethrough = true, fg = "#6c7086", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTLinkText", { fg = "#89dceb", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTLinkUrl", { fg = "#6c7086", underline = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTCodeLang", { fg = "#ffffff", bg = "#45475a", bold = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTDiffAdd", { fg = "#a6e3a1", bg = "#1e3a2f", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTDiffDel", { fg = "#f38ba8", bg = "#3a1e2f", default = true })
  vim.api.nvim_set_hl(0, "ChatGPTSenderUser", { fg = "#89b4fa", bold = true, default = true })
  vim.api.nvim_set_hl(0, "ChatGPTSenderAssistant", { fg = "#a6e3a1", bold = true, default = true })

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

-- Context APIs (deprecated but kept for backwards compatibility)
M.add_context = function()
  local lsp_context = require("chatgpt.context.lsp")
  lsp_context.get_context(function(item)
    if item then
      local Context = require("chatgpt.context")
      local ref = Context.make_ref(item)
      Context.add(ref, item)
      vim.notify(string.format("Context added: %s", ref), vim.log.levels.INFO)
    end
  end)
end

M.add_project_context = function()
  local project_context = require("chatgpt.context.project")
  local item = project_context.get_context()
  if item then
    local Context = require("chatgpt.context")
    local ref = Context.make_ref(item)
    Context.add(ref, item)
    vim.notify(string.format("Context added: %s", ref), vim.log.levels.INFO)
  end
end

return M
