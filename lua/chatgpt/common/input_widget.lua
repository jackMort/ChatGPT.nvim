local Input = require("nui.input")
local Config = require("chatgpt.config")

return function(name, on_submit)
  local input = Input({
    zindex = 100,
    position = "50%",
    size = {
      width = 60,
    },
    relative = "editor",
    border = {
      style = "rounded",
      text = {
        top = " " .. name .. " ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = Config.options.popup_input.prompt,
    on_submit = on_submit,
  })

  return input
end
