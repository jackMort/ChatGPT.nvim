local Config = require("chatgpt.config")

local M = {}

function M.setup()
  vim.cmd([[sign define chatgpt_action_start_block text=┌ texthl=ErrorMsg linehl=BufferLineBackground]])
  vim.cmd([[sign define chatgpt_action_middle_block text=│ texthl=ErrorMsg linehl=BufferLineBackground]])
  vim.cmd([[sign define chatgpt_action_end_block text=└ texthl=ErrorMsg linehl=BufferLineBackground]])

  vim.cmd([[sign define chatgpt_chat_start_block text=┌ texthl=Constant]])
  vim.cmd([[sign define chatgpt_chat_middle_block text=│ texthl=Constant]])
  vim.cmd([[sign define chatgpt_chat_end_block text=└ texthl=Constant]])

  vim.cmd("sign define chatgpt_question_sign text=" .. Config.options.chat.question_sign .. " texthl=ChatGPTQuestion")
end

function M.set(name, bufnr, line)
  pcall(vim.fn.sign_place, 0, "chatgpt_ns", name, bufnr, { lnum = line + 1 })
end

function M.del(bufnr)
  pcall(vim.fn.sign_unplace, "chatgpt_ns", { buffer = bufnr })
end

function M.set_for_lines(bufnr, start_line, end_line, type)
  if start_line == end_line or end_line < start_line then
    M.set("chatgpt_" .. type .. "_middle_block", bufnr, start_line)
  else
    M.set("chatgpt_" .. type .. "_start_block", bufnr, start_line)
    M.set("chatgpt_" .. type .. "_end_block", bufnr, end_line)
  end
  if start_line + 1 < end_line then
    for j = start_line + 1, end_line - 1, 1 do
      M.set("chatgpt_" .. type .. "_middle_block", bufnr, j)
    end
  end
end

return M
