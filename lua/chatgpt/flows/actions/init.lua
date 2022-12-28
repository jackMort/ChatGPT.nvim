local M = {}

local CompletionAction = require("chatgpt.flows.actions.completions")
local Config = require("chatgpt.config")

GRAMMAR_CORRECTION = [[
Correct this to standard English:

{{input}}
]]

TRANSLATE = [[
Translate this into {{lang}}:

{{input}}
]]

KEYWORDS = [[
Convert into emoji.

]]

WRITE_DOCSTRING = [[
# An elaborate, high quality docstring for the above function:
# Writing a good docstring

This is an example of writing a really good docstring that follows a best practice for the given language. Attention is paid to detailing things like 
* parameter and return types (if applicable)
* any errors that might be raised or returned, depending on the language

I received the following code:

```{{filetype}}
{{input}}
```

The code with a really good docstring added is below:

```{{filetype}}
]]

SUMMARIZE_TEXT = [[
Summarize the following text.

Text:
"""
{{input}}
"""

Summary:
]]

ADD_TESTS = [[
Implement tests for the following code.

Code:
```{{filetype}}
{{input}}
```

Tests:
```{{filetype}}
]]

OPTIMIZE_CODE = [[
Optimize the following code.

Code:
```{{filetype}}
{{input}}
```

Optimized version:
```{{filetype}}
]]

FIX_BUGS = [[
Fix bugs in the below code

Code:
```{{filetype}}
{{input}}
```

Fixed code:
```{{filetype}}
]]

EXPLAIN_CODE = [[
Explain the following code:

Code:
```{{filetype}}
{{input}}
```

Here's what the above code is doing:
```
]]

CUSTOM_CODE_ACTION = [[
I have the following code:
```{{filetype}}
{{input}}
```

{{instruction}}:
```
]]

function M.run_action(opts)
  local ACTIONS = {
    grammar_correction = {
      class = CompletionAction,
      opts = {
        template = GRAMMAR_CORRECTION,
        params = {
          model = "text-davinci-003",
        },
      },
    },
    translate = {
      class = CompletionAction,
      opts = {
        template = TRANSLATE,
        params = {
          model = "text-davinci-003",
          temperature = 0.3,
        },
      },
      args = {
        lang = { type = "string", optional = "true", default = "english" },
      },
    },
    keywords = {
      class = CompletionAction,
      opts = {
        template = KEYWORDS,
        params = {
          model = "text-davinci-003",
          temperature = 0.5,
          frequency_penalty = 0.8,
        },
      },
    },
    docstring = {
      class = CompletionAction,
      opts = {
        template = WRITE_DOCSTRING,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
      },
    },
    add_tests = {
      class = CompletionAction,
      opts = {
        strategy = "append",
        template = ADD_TESTS,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
      },
    },
    optimize_code = {
      class = CompletionAction,
      opts = {
        template = OPTIMIZE_CODE,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
      },
    },
    summarize = {
      class = CompletionAction,
      opts = {
        template = SUMMARIZE_TEXT,
        params = {
          model = "text-davinci-003",
        },
      },
    },
    fix_bugs = {
      class = CompletionAction,
      opts = {
        template = FIX_BUGS,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
      },
    },

    explain_code = {
      class = CompletionAction,
      opts = {
        strategy = "display",
        template = EXPLAIN_CODE,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
      },
    },
  }

  local key = opts.fargs[1]
  local item = ACTIONS[key]

  --
  -- parse args
  --
  if item.args then
    item.opts.variables = {}
    local i = 2
    for key, value in pairs(item.args) do
      local arg = opts.fargs[i]
      -- TODO: validataion
      item.opts.variables[key] = arg or value.default or ""
      i = i + 1
    end
  end

  opts = vim.tbl_extend("force", {}, opts, item.opts)
  local action = item.class.new(opts)
  action:run()
end

function M.run_custom_code_action(opts)
  local Input = require("nui.input")

  local input = Input({
    position = "50%",
    size = {
      width = 60,
    },
    border = {
      style = "rounded",
      text = {
        top = " Custom Code Action ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
  }, {
    prompt = Config.options.chat_input.prompt,
    on_submit = function(value)
      opts = vim.tbl_extend("force", {}, opts, {
        template = CUSTOM_CODE_ACTION,
        params = {
          model = "code-davinci-002",
          stop = { "```" },
        },
        variables = {
          instruction = value,
        },
      })
      local action = CompletionAction.new(opts)
      action:run()
    end,
  })

  local close_keymaps = Config.options.keymaps.close
  if type(close_keymaps) ~= "table" then
    close_keymaps = { close_keymaps }
  end

  for _, keymap in ipairs(close_keymaps) do
    input:map("i", keymap, function()
      input.input_props.on_close()
    end, { noremap = true, silent = true })
  end

  input:mount()
end

return M
