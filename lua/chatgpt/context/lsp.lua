local M = {}

local Config = require("chatgpt.config")

-- Get the word under cursor
local function get_word_under_cursor()
  return vim.fn.expand("<cword>")
end

-- Read lines from a file
local function read_file_lines(file, start_line, end_line)
  local lines = {}
  local f = io.open(file, "r")
  if not f then
    return nil
  end

  local line_num = 0
  for line in f:lines() do
    line_num = line_num + 1
    if line_num >= start_line and line_num <= end_line then
      table.insert(lines, line)
    end
    if line_num > end_line then
      break
    end
  end

  f:close()
  return table.concat(lines, "\n")
end

-- Extract definition content from location
local function extract_definition(location, max_lines)
  local uri = location.uri or location.targetUri
  local range = location.range or location.targetSelectionRange or location.targetRange

  if not uri or not range then
    return nil
  end

  local file = vim.uri_to_fname(uri)
  local start_line = range.start.line + 1 -- LSP is 0-indexed

  -- Read up to max_lines from the definition start
  local content = read_file_lines(file, start_line, start_line + max_lines - 1)

  -- Get relative path for display
  local cwd = vim.fn.getcwd()
  local relative_path = file
  if vim.startswith(file, cwd) then
    relative_path = file:sub(#cwd + 2)
  end

  return {
    content = content,
    file = relative_path,
    line = start_line,
  }
end

-- Get LSP definition context for symbol under cursor
-- Calls callback with item or nil
function M.get_context(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local word = get_word_under_cursor()

  if word == "" then
    vim.notify("No symbol under cursor", vim.log.levels.WARN)
    if callback then
      callback(nil)
    end
    return
  end

  -- Check if LSP is attached
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    vim.notify("No LSP client attached to buffer", vim.log.levels.WARN)
    if callback then
      callback(nil)
    end
    return
  end

  local params = vim.lsp.util.make_position_params()

  vim.lsp.buf_request(bufnr, "textDocument/definition", params, function(err, result, _, _)
    if err then
      vim.notify("LSP error: " .. vim.inspect(err), vim.log.levels.ERROR)
      if callback then
        callback(nil)
      end
      return
    end

    if not result or (type(result) == "table" and #result == 0) then
      vim.notify("No definition found for: " .. word, vim.log.levels.WARN)
      if callback then
        callback(nil)
      end
      return
    end

    -- Handle both single result and array
    local location = result
    if type(result) == "table" and result[1] then
      location = result[1]
    end

    local max_lines = Config.options.context and Config.options.context.lsp and Config.options.context.lsp.max_lines
      or 50

    local definition = extract_definition(location, max_lines)

    if not definition or not definition.content then
      vim.notify("Could not read definition for: " .. word, vim.log.levels.WARN)
      if callback then
        callback(nil)
      end
      return
    end

    local item = {
      type = "lsp",
      name = word,
      file = definition.file,
      line = definition.line,
      content = definition.content,
    }

    if callback then
      callback(item)
    end
  end)
end

return M
