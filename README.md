# ChatGPT.nvim

![GitHub Workflow Status](http://img.shields.io/github/actions/workflow/status/jackMort/ChatGPT.nvim/default.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

`ChatGPT` is a Neovim plugin that allows you to interact with OpenAI's GPT-3 language model.
With `ChatGPT`, you can ask questions and get answers from GPT-3 in real-time.

![preview image](https://github.com/jackMort/ChatGPT.nvim/blob/media/preview-2.png?raw=true)
## Installation

- Make sure you have `curl` installed.
- Set environment variable called `$OPENAI_API_KEY` which you can [obtain here](https://beta.openai.com/account/api-keys).

```lua
-- Packer
use({
  "jackMort/ChatGPT.nvim",
    config = function()
      require("chatgpt").setup()
    end,
    requires = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    }
})

-- Lazy
{
  "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup()
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    }
}
```

## Configuration

`ChatGPT.nvim` comes with the following defaults, you can override them by passing config as setup param

```lua
{
  welcome_message = WELCOME_MESSAGE,
  loading_text = "loading",
  question_sign = "", -- you can use emoji if you want e.g. 🙂
  answer_sign = "ﮧ", -- 🤖
  max_line_length = 120,
  yank_register = "+",
  chat_layout = {
    relative = "editor",
    position = "50%",
    size = {
      height = "80%",
      width = "80%",
    },
  },
  settings_window = {
    border = {
      style = "rounded",
      text = {
        top = " Settings ",
      },
    },
  },
  chat_window = {
    filetype = "chatgpt",
    border = {
      highlight = "FloatBorder",
      style = "rounded",
      text = {
        top = " ChatGPT ",
      },
    },
  },
  chat_input = {
    prompt = "  ",
    border = {
      highlight = "FloatBorder",
      style = "rounded",
      text = {
        top_align = "center",
        top = " Prompt ",
      },
    },
  },
  openai_params = {
    model = "gpt-3.5-turbo",
    frequency_penalty = 0,
    presence_penalty = 0,
    max_tokens = 300,
    temperature = 0,
    top_p = 1,
    n = 1,
  },
  openai_edit_params = {
    model = "code-davinci-edit-001",
    temperature = 0,
    top_p = 1,
    n = 1,
  },
  keymaps = {
    close = { "<C-c>" },
    submit = "<C-Enter>",
    yank_last = "<C-y>",
    yank_last_code = "<C-k>",
    scroll_up = "<C-u>",
    scroll_down = "<C-d>",
    toggle_settings = "<C-o>",
    new_session = "<C-n>",
    cycle_windows = "<Tab>",
    -- in the Sessions pane
    select_session = "<Space>",
    rename_session = "r",
    delete_session = "d",
  },
  predefined_chat_gpt_prompts = "https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv",
  actions_paths = {"~/.config/nvim/custom_actions.json"}
}
```
## Usage

Plugin exposes following commands:

#### `ChatGPT`
`ChatGPT` command which opens interactive window using the `gpt-3.5-turbo`
model.
(also known as `ChatGPT`)

#### `ChatGPTActAs`
`ChatGPTActAs` command which opens a prompt selection from [Awesome ChatGPT Prompts](https://github.com/f/awesome-chatgpt-prompts) to be used with the `gpt-3.5-turbo` model.

![preview image](https://github.com/jackMort/ChatGPT.nvim/blob/media/preview-3.png?raw=true)

#### `ChatGPTEditWithInstructions`
`ChatGPTEditWithInstructions` command which opens interactive window to edit selected text or whole window using the `code-davinci-edit-002` model (GPT 3.5 fine-tuned for coding).

You can map it usig the Lua API, e.g. using `which-key.nvim`:
```lua
local chatgpt = require("chatgpt")
wk.register({
    p = {
        name = "ChatGPT",
        e = {
            function()
                chatgpt.edit_with_instructions()
            end,
            "Edit with instructions",
        },
    },
}, {
    prefix = "<leader>",
    mode = "v",
})
```

- [demo video](https://www.youtube.com/watch?v=dWe01EV0q3Q).

![preview image](https://github.com/jackMort/ChatGPT.nvim/blob/media/preview.png?raw=true)

#### `ChatGPTRun`

`ChatGPTRun [action]` command which runs specific actions -- see [`actions.json`](blob/main/lua/chatgpt/flows/actions/actions.json) file for a detailed list. Available actions are:
  1. `grammar_correction`
  2. `translate`
  3. `keywords`
  4. `docstring`
  5. `add_tests`
  6. `optimize_code`
  7. `summarize`
  8. `fix_bugs`
  9. `explain_code`
  10. `roxygen_edit`

All the above actions are using `gpt-3.5-turbo` model.

It is possible to define custom actions with a JSON file. See [`actions.json`](blob/main/lua/chatgpt/flows/actions/actions.json) for an example. The path of custom actions can be set in the config (see `actions_paths` field in the cofig example above).

#### `ChatGPTRunCustomCodeAction`
TODO

### Interactive popup
When using `ChatGPT` and `ChatGPTEditWithInstructions`, the following
keybindings are available:
- `<C-Enter>` to submit.
- `<C-c>` to close chat window.
- `<C-u>` scroll up chat window.
- `<C-d>` scroll down chat window.
- `<C-y>` to copy/yank last answer.
- `<C-k>` to copy/yank code from last answer.
- `<C-o>` Toggle settings window.
- `<C-n>` Start new session.
- `<Tab>` Cycle over windows.
- `<C-i>` [Edit Window] use response as input.

When the setting window is opened (with `<C-o>`), settigs can be modified by
pressing `Enter` on the related config. Settings are saved across sections

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/jackMort)
