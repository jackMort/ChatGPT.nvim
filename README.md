# ChatGPT.nvim [WIP]

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)![GitHub Workflow Status](https://img.shields.io/github/workflow/status/jackMort/ChatGPT.nvim/default?style=for-the-badge)

`ChatGPT` is a Neovim plugin that allows you to interact with OpenAI's GPT-3 language model.
With `ChatGPT`, you can ask questions and get answers from GPT-3 in real-time.

![preview image](https://github.com/jackMort/ChatGPT.nvim/blob/media/preview.png)
## Installation

- Make sure you have `curl` installed.
- Set environment variable called `$OPENAI_API_KEY` which you can [optain
here](https://beta.openai.com/account/api-keys).

```lua
-- Packer
use({
  "jackMort/ChatGPT.nvim",
    config = function()
      require("chatgpt").setup({})
    end,
    requires = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
    }
})
```

## Configuration

_Not available yet, work in progress_

## Usage

Plugin exposes `ChatGPT` command which opens interactive window. Available keybindings for that window are:
- `<C-c>` to close chat window.
- `<C-y>` to copy/yank last answer.

## TODO

- configuration
- error handling
- using visual selected text to feed chat
- ...


[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/jackMort)
