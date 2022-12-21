local M = {}

function M.setup()
  vim.cmd([[sign define chatgpt_start_block text=┌ texthl=ErrorMsg linehl=BufferLineBackground]])
  vim.cmd([[sign define chatgpt_middle_block text=│ texthl=ErrorMsg linehl=BufferLineBackground]])
  vim.cmd([[sign define chatgpt_end_block text=└ texthl=ErrorMsg linehl=BufferLineBackground]])
end

function M.set(name, bufnr, line)
  pcall(vim.fn.sign_place, 0, "chatgpt_ns", name, bufnr, { lnum = line + 1 })
end

function M.del(bufnr)
  pcall(vim.fn.sign_unplace, "chatgpt_ns", { buffer = bufnr })
end

function M.set_for_lines(bufnr, start_line, end_line)
  if start_line == end_line or end_line < start_line then
    M.set("chatgpt_middle_block", bufnr, start_line)
  else
    M.set("chatgpt_start_block", bufnr, start_line)
    M.set("chatgpt_end_block", bufnr, end_line)
  end
  if start_line + 1 < end_line then
    for j = start_line + 1, end_line - 1, 1 do
      M.set("chatgpt_middle_block", bufnr, j)
    end
  end
end

return M
