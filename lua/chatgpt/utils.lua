local M = {}

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
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

function M.wrapText(text, maxLineLength)
  local lines = M.wrapTextToTable(text, maxLineLength)
  return table.concat(lines, "\n")
end

function M.trimText(text, maxLength)
  if #text > maxLength then
    return string.sub(text, 1, maxLength - 3) .. "..."
  else
    return text
  end
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

function M.get_visual_lines(bufnr)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.api.nvim_feedkeys(ESC_FEEDKEY, "n", true)

  local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, "<"))
  local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(bufnr, ">"))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

  -- get whole buffer if there is no current/previous visual selection
  if start_row == 0 then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    start_row = 1
    start_col = 0
    end_row = #lines
    end_col = #lines[#lines]
  end

  -- use 1-based indexing and handle selections made in visual line mode (see :help getpos)
  start_col = start_col + 1
  end_col = math.min(end_col, #lines[#lines] - 1) + 1

  -- shorten first/last line according to start_col/end_col
  lines[#lines] = lines[#lines]:sub(1, end_col)
  lines[1] = lines[1]:sub(start_col)

  return lines, start_row, start_col, end_row, end_col
end

function M.count_newlines_at_end(str)
  local start, stop = str:find("\n*$")
  return (stop - start + 1) or 0
end

function M.replace_newlines_at_end(str, num)
  local res = str:gsub("\n*$", string.rep("\n", num), 1)
  return res
end

function M.change_mode_to_normal()
        vim.api.nvim_feedkeys(ESC_FEEDKEY, 'n', false)
end

function M.change_mode_to_insert()
        vim.api.nvim_command('startinsert')
end

return M
