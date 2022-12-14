local chatgpt = require("chatgpt")

vim.api.nvim_create_user_command("ChatGPT", chatgpt.openChat, {})
