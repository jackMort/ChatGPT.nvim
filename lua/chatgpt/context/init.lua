local M = {}

-- Current context items (shared across chat sessions until cleared)
M.items = {}

-- Add a context item
-- @param item table { type = "lsp"|"project", name = string, file = string?, line = number?, content = string }
function M.add(item)
  table.insert(M.items, item)
end

-- Remove a context item by index
function M.remove(index)
  if index > 0 and index <= #M.items then
    table.remove(M.items, index)
  end
end

-- Clear all context items
function M.clear()
  M.items = {}
end

-- Get all context items
function M.get_items()
  return M.items
end

-- Get context count
function M.count()
  return #M.items
end

-- Check if there's any context
function M.has_context()
  return #M.items > 0
end

-- Format compact references for display (@file:line)
function M.format_references()
  if #M.items == 0 then
    return nil
  end

  local refs = {}
  for _, item in ipairs(M.items) do
    if item.type == "lsp" then
      table.insert(refs, string.format("@%s:%d", item.file or item.name, item.line or 0))
    elseif item.type == "project" then
      table.insert(refs, "@" .. item.name)
    end
  end

  if #refs == 0 then
    return nil
  end

  return table.concat(refs, " ")
end

-- Format context for injection into message
function M.format_for_message()
  if #M.items == 0 then
    return nil
  end

  local parts = {}

  for _, item in ipairs(M.items) do
    local content = item.content or ""
    if item.type == "lsp" then
      local location = item.file or "unknown"
      if item.line then
        location = location .. ":" .. item.line
      end
      table.insert(parts, string.format("# %s (%s)\n```\n%s\n```", item.name or "unknown", location, content))
    elseif item.type == "project" then
      table.insert(parts, string.format("# Project: %s\n%s", item.name or "unknown", content))
    end
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, "\n\n")
end

return M
