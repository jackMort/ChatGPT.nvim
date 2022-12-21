-- Credits: https://github.com/charmbracelet/bubbles/blob/master/spinner/spinner.go

local Spinner = {}
Spinner.__index = Spinner

function Spinner.types()
  return {
    line = {
      frames = { "|", "/", "-", "\\" },
      fps = 10,
    },
    dot = {
      frames = { "⣾ ", "⣽ ", "⣻ ", "⢿ ", "⡿ ", "⣟ ", "⣯ ", "⣷ " },
      fps = 10,
    },
    minidot = {
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      fps = 12,
    },
    jump = {
      frames = { "⢄", "⢂", "⢁", "⡁", "⡈", "⡐", "⡠" },
      fps = 10,
    },
    pulse = {
      frames = { "█", "▓", "▒", "░" },
      fps = 8,
    },
    points = {
      frames = { "∙∙∙", "●∙∙", "∙●∙", "∙∙●" },
      fps = 7,
    },
    globe = {
      frames = { "🌍", "🌎", "🌏" },
      fps = 4,
    },

    moon = {
      frames = { "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },
      fps = 8,
    },
    monkey = {
      frames = { "🙈", "🙉", "🙊" },
      fps = 3,
    },
    meter = {
      frames = {
        "▱▱▱",
        "▰▱▱",
        "▰▰▱",
        "▰▰▰",
        "▰▰▱",
        "▰▱▱",
        "▱▱▱",
      },
      fps = 7,
    },
    hamburger = {
      frames = { "☱", "☲", "☴", "☲" },
      fps = 3,
    },
  }
end

function Spinner:new(render_fn, opts)
  opts = opts or {}
  opts.animation_type_name = opts.animation_type_name or "points"
  opts.text = opts.text or ""

  self = setmetatable({}, Spinner)
  self.animation_type = Spinner.types()[opts.animation_type_name]
  self.render_fn = render_fn
  self.text = opts.text
  self.timer = nil
  self.frame = 1

  return self
end

function Spinner:update()
  if self.frame > #self.animation_type.frames then
    self.frame = 1
  end
  self.render_fn(self:to_string())
  self.frame = self.frame + 1
end

function Spinner:stop()
  if self.timer ~= nil then
    self.timer:stop()
    self.timer = nil
  end
end

function Spinner:start()
  self.timer = vim.loop.new_timer()
  self.timer:start(0, 1000 / self.animation_type.fps, function()
    self:update()
  end)
end

function Spinner:is_running()
  return self.timer ~= nil
end

function Spinner:to_string()
  if self.text == "" then
    return self.animation_type.frames[self.frame]
  end
  return self.animation_type.frames[self.frame] .. " " .. self.text
end

return Spinner
