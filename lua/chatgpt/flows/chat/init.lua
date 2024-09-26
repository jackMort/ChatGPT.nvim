local Session = require("chatgpt.flows.chat.session")
local Prompts = require("chatgpt.prompts")
local Chat = require("chatgpt.flows.chat.base")

local ROLE_TO_CODE = {
  ["user"] = 1,
  ["assistant"] = 2,
  ["system"] = 3,
}

local M = {
  chat = nil,
}

M.open = function()
  if M.chat ~= nil and M.chat.active then
    M.chat:toggle()
  else
    M.chat = Chat:new()
    M.chat:open()
  end
end

M.open_with_awesome_prompt = function()
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      -- create new named session
      local session = Session.new({ name = act })
      session:save()

      local chat = Chat:new()
      chat:open()
      chat.chat_window.border:set_text("top", " ChatGPT - Acts as " .. act .. " ", "center")

      chat:set_system_message(prompt)
      chat:open_system_panel()
    end),
  })
end

-- @param opts.new_session default false
-- @param opts.messages optinal (effect when new session), prompt content list, like [{"role": "system", "content": "You are a helpful assistant."},{"role": "user", "content": "Hello!"}]
-- @param opts.open_system_panel "open" or "active"
M.open_with = function(opts)
  local new_session = false
  if M.chat ~= nil and M.chat.active then
    M.chat:toggle()
  else
    M.chat = Chat:new()
    M.chat:open()
    new_session = true
  end
  if opts and M.chat.layout.winid ~= nil then
    if opts.new_session then
      M.chat:new_session()
    end

    -- 仅在new_session时才支持prompt设置
    if new_session or opts.new_session then
      if opts.messages then
        for _, item in pairs(opts.messages) do
          if item and item.role == "system" then
            M.chat:set_system_message(item.content)
          elseif item and item.role and ROLE_TO_CODE[item.role] then
            M.chat:add(ROLE_TO_CODE[item.role], item.content)
          end
        end
      end
    end

    if opts.open_system_panel == "open" or opts.open_system_panel == "active" then
      M.chat.system_role_open = true
      M.chat:redraw()
      if opts.open_system_panel == "active" then
        M.chat:set_active_panel(M.chat.system_role_panel)
      end
    end
  end
end

return M
