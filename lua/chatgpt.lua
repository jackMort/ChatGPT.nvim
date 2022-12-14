-- main module file
local module = require("chatgpt.module")
local config = require("chatgpt.config")

local M = {}

M.setup = function(options)
  config.setup(options)
end

--
-- public methods for the plugin
--

M.openChat = function()
  module.openChat()
end

return M
