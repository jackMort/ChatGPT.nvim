# ChatGPT.nvim [WIP]

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/jackMort/ChatGPT.nvim/default?style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

`ChatGPT` is a Neovim plugin that allows you to interact with OpenAI's GPT-3 language model.
With `ChatGPT`, you can ask questions and get answers from GPT-3 in real-time.

![preview image](https://github.com/jackMort/ChatGPT.nvim/blob/media/preview.png)
## Installation

- Make sure you have `curl` installed.
- Set environment variable called `$OPENAI_API_KEY` which you can [obtain here](https://beta.openai.com/account/api-keys).

```lua
-- Packer
use({
  "jackMort/ChatGPT.nvim",
    config = function()
      require("chatgpt").setup({
        -- optional configuration
      })
    end,
    requires = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
    }
})
```

## Configuration

`ChatGPT.nvim` comes with the following defaults

```lua
{
  welcome_message = WELCOME_MESSAGE, -- set to "" if you don't like the fancy robot
  loading_text = "loading",
  question_sign = "", -- you can use emoji if you want e.g. 🙂
  answer_sign = "ﮧ", -- 🤖
  max_line_length = 120,
  chat_layout = {
    relative = "editor",
    position = "50%",
    size = {
      height = "80%",
      width = "80%",
    },
  },
  chat_window = {
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
    win_options = {
      winhighlight = "Normal:Normal",
    },
  },
  openai_params = {
    model = "text-davinci-003",
    frequency_penalty = 0,
    presence_penalty = 0,
    max_tokens = 300,
    temperature = 0,
    top_p = 1,
    n = 1,
  },
}
```
## Usage

Plugin exposes `ChatGPT` command which opens interactive window. Available keybindings for that window are:
- `<C-c>` to close chat window.
- `<C-y>` to copy/yank last answer.


[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/jackMort)
