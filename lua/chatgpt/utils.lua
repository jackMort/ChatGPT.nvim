local M = {}

function M.split(text)
  local t = {}
  for str in string.gmatch(text, "%S+") do
    table.insert(t, str)
  end
  return t
end

function M.splitLines(text)
  local lines = {}
  for line in string.gmatch(text, "[^\n]+") do
    table.insert(lines, line)
  end
  return lines
end

function M.wrapText(text, maxLineLength)
  local lines = {}

  local textByLines = M.splitLines(text)
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

  return table.concat(lines, "\n")
end

return M
