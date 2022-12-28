local M = {}

local MAX_COL = 2147483647
local ESC_FEEDKEY = vim.api.nvim_replace_termcodes("<ESC>", true, false, true)

function M.split(text)
  local t = {}
  for str in string.gmatch(text, "%S+") do
    table.insert(t, str)
  end
  return t
end

function M.split_string_by_line(text)
  local lines = {}
  for line in text:gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end
  return lines
end

function M.wrapText(text, maxLineLength)
  local lines = M.wrapTextToTable(text, maxLineLength)
  return table.concat(lines, "\n")
end

function M.wrapTextToTable(text, maxLineLength)
  local lines = {}

  local textByLines = M.split_string_by_line(text)
  for _, line in ipairs(textByLines) do
    if #line > maxLineLength then
      local tmp_line = ""
      local words = M.split(line)
      for _, word in ipairs(words) do
        if #tmp_line + #word + 1 > maxLineLength then
          table.insert(lines, tmp_line)
          tmp_line = word
        else
          tmp_line = tmp_line .. " " .. word
        end
      end
      table.insert(lines, tmp_line)
    else
      table.insert(lines, line)
    end
  end
  return lines
end

function M.get_end_col(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1]
  return #line
end

function M.paste(bufnr, start_row, start_col, end_row, lines)
  local end_col
  if end_row > 0 then
    end_col = M.get_end_col(bufnr, end_row)
  else
    local line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
    end_col = #line
  end

  vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
end

function M.get_visual_lines(bufnr)
  local start_row, start_col, end_row, end_col = M.get_visual_start_end()
  if start_row == end_row and start_col == end_col then
    return nil
  end

  local visual_lines = M.get_lines(bufnr, start_row, start_col, end_row, end_col)
  return visual_lines, start_row, start_col, end_row, end_col
end

-- credentials https://github.com/jameshiew/nvim-magic/
function M.get_visual_start_end()
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))

  -- handle selections made in visual line mode (see :help getpos)
  if end_col == MAX_COL then
    end_col = M.get_end_col(0, end_row)
  end

  return start_row, start_col, end_row, end_col
end

-- gets full and partial lines between start and end
function M.get_lines(bufnr, start_row, start_col, end_row, end_col)
  if start_row == end_row and start_col == end_col then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
  lines[1] = lines[1]:sub(start_col, -1)
  if #lines == 1 then -- visual selection all in the same line
    lines[1] = lines[1]:sub(1, end_col - start_col + 1)
  else
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end
  return lines
end

return M
