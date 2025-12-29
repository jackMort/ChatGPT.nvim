local M = {}

local Context = require("chatgpt.context")
local Config = require("chatgpt.config")

-- Manifest files to detect project type
local MANIFEST_FILES = {
  ["package.json"] = "javascript",
  ["Cargo.toml"] = "rust",
  ["go.mod"] = "go",
  ["pyproject.toml"] = "python",
  ["setup.py"] = "python",
  ["requirements.txt"] = "python",
  ["Gemfile"] = "ruby",
  ["composer.json"] = "php",
  ["pom.xml"] = "java",
  ["build.gradle"] = "java",
  ["CMakeLists.txt"] = "cpp",
  ["Makefile"] = "make",
}

-- Default context files to search for
local DEFAULT_CONTEXT_FILES = {
  ".chatgpt.md",
  ".cursorrules",
  ".github/copilot-instructions.md",
}

-- Read file contents
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*all")
  f:close()
  return content
end

-- Check if file exists
local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Find project root (look for .git or manifest files)
local function find_project_root()
  local cwd = vim.fn.getcwd()

  -- Check for .git directory
  local git_dir = vim.fn.finddir(".git", cwd .. ";")
  if git_dir ~= "" then
    return vim.fn.fnamemodify(git_dir, ":h")
  end

  -- Fall back to cwd
  return cwd
end

-- Detect project type from manifest files
function M.detect_project_type()
  local root = find_project_root()
  local detected = {}

  for manifest, lang in pairs(MANIFEST_FILES) do
    local path = root .. "/" .. manifest
    if file_exists(path) then
      table.insert(detected, { file = manifest, language = lang })
    end
  end

  return detected, root
end

-- Generate project summary from detected manifests
function M.generate_summary()
  local detected, root = M.detect_project_type()

  if #detected == 0 then
    return nil
  end

  local languages = {}
  local details = {}

  for _, d in ipairs(detected) do
    if not vim.tbl_contains(languages, d.language) then
      table.insert(languages, d.language)
    end

    -- Try to extract more details from package.json
    if d.file == "package.json" then
      local content = read_file(root .. "/package.json")
      if content then
        local ok, json = pcall(vim.json.decode, content)
        if ok and json then
          if json.dependencies then
            -- Detect common frameworks
            if json.dependencies.react then
              table.insert(details, "React")
            end
            if json.dependencies.vue then
              table.insert(details, "Vue")
            end
            if json.dependencies.svelte then
              table.insert(details, "Svelte")
            end
            if json.dependencies.express then
              table.insert(details, "Express")
            end
            if json.dependencies.next then
              table.insert(details, "Next.js")
            end
          end
          if json.devDependencies then
            if json.devDependencies.typescript then
              -- Replace javascript with typescript
              for i, l in ipairs(languages) do
                if l == "javascript" then
                  languages[i] = "typescript"
                end
              end
            end
            if json.devDependencies.tailwindcss then
              table.insert(details, "Tailwind")
            end
            if json.devDependencies.vite then
              table.insert(details, "Vite")
            end
          end
        end
      end
    end

    -- Extract from Cargo.toml
    if d.file == "Cargo.toml" then
      local content = read_file(root .. "/Cargo.toml")
      if content then
        -- Simple pattern matching for common crates
        if content:match('%[dependencies%][^%[]*tokio') then
          table.insert(details, "Tokio")
        end
        if content:match('%[dependencies%][^%[]*actix') then
          table.insert(details, "Actix")
        end
      end
    end
  end

  -- Build summary string
  local lang_str = table.concat(languages, "/")
  local summary = lang_str:sub(1, 1):upper() .. lang_str:sub(2) .. " project"

  if #details > 0 then
    summary = summary .. " using " .. table.concat(details, ", ")
  end

  return summary
end

-- Find and read context file
function M.find_context_file()
  local root = find_project_root()
  local context_files = Config.options.context
      and Config.options.context.project
      and Config.options.context.project.context_files
    or DEFAULT_CONTEXT_FILES

  for _, filename in ipairs(context_files) do
    local path = root .. "/" .. filename
    if file_exists(path) then
      local content = read_file(path)
      if content then
        return {
          name = filename,
          content = content,
        }
      end
    end
  end

  return nil
end

-- Add project context
function M.add_context()
  local context_file = M.find_context_file()

  if not context_file then
    vim.notify("No project context file found", vim.log.levels.WARN)
    return false
  end

  -- Check if already added
  for _, item in ipairs(Context.get_items()) do
    if item.type == "project" and item.name == context_file.name then
      vim.notify("Project context already added: " .. context_file.name, vim.log.levels.INFO)
      return false
    end
  end

  Context.add({
    type = "project",
    name = context_file.name,
    content = context_file.content,
  })

  vim.notify("Added project context: " .. context_file.name)
  return true
end

return M
