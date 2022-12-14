-- main module file
local module = require("chatgpt.module")

local M = {}
M.config = {
  -- default config
}

-- setup is the public method to setup your plugin
M.setup = function(args)
  -- you can define your setup function here. Usually configurations can be merged, accepting outside params and
  -- you can also put some validation here for those.
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

--
-- public methods for the plugin
--

M.complete = function()
  module.complete(M.config)
end

return M
