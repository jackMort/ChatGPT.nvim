local M = {}

-- Context storage keyed by reference string (e.g., "@file.lua:42")
M.refs = {}

-- Add a context item with its reference key
function M.add(ref, item)
  M.refs[ref] = item
end

-- Get context by reference
function M.get(ref)
  return M.refs[ref]
end

-- Remove a context item by reference
function M.remove(ref)
  M.refs[ref] = nil
end

-- Clear all context
function M.clear()
  M.refs = {}
end

-- Generate reference string for an item
function M.make_ref(item)
  if item.type == "lsp" then
    return string.format("@%s:%d", item.file or item.name, item.line or 0)
  elseif item.type == "project" then
    return "@" .. item.name
  elseif item.type == "file" then
    return "@" .. (item.file or item.name)
  end
  return "@unknown"
end

-- Format a single context item for API
local function format_item(item)
  local content = item.content or ""
  if item.type == "lsp" then
    local location = item.file or "unknown"
    if item.line then
      location = location .. ":" .. item.line
    end
    return string.format("# %s (%s)\n```\n%s\n```", item.name or "unknown", location, content)
  elseif item.type == "project" then
    return string.format("# Project: %s\n%s", item.name or "unknown", content)
  elseif item.type == "file" then
    return string.format("# File: %s\n```\n%s\n```", item.file or item.name or "unknown", content)
  end
  return content
end

-- Find all @references in text and expand them for API
-- Returns: api_text (expanded), display_text (original)
function M.expand_refs(text)
  if not text or text == "" then
    return text, text
  end

  local refs_content = {}
  local seen = {}

  for ref in text:gmatch("@[^%s]+") do
    if M.refs[ref] and not seen[ref] then
      seen[ref] = true
      table.insert(refs_content, format_item(M.refs[ref]))
    end
  end

  if #refs_content == 0 then
    return text, text
  end

  local context_block = table.concat(refs_content, "\n\n")
  local api_text = context_block .. "\n\n---\n\n" .. text

  return api_text, text
end

return M
