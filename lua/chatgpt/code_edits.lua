local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Utils = require("chatgpt.utils")
local Spinner = require("chatgpt.spinner")
local Settings = require("chatgpt.settings")

EDIT_FUNCTION_ARGUMENTS = {
  function_call = {
    name = "apply_code_changes",
  },
  functions = {
    {
      name = "apply_code_changes",
      description = "Apply changes to the provided code based on the provided instructions, and briefly describe the edits.",
      parameters = {
        type = "object",
        properties = {
          changed_code = {
            type = "string",
            description = "The changed code.",
          },
          applied_changes = {
            type = "string",
            description = "Brief descriptions of the edits applied to the original code, formatted as a bullet list.",
          },
        },
      },
      required = { "changed_code", "applied_changes" },
    },
  },
}

-- https://openai.com/blog/gpt-4-api-general-availability
local build_edit_messages = function(input, instructions, use_functions_for_edits)
  local system_message_content
  if use_functions_for_edits then
    system_message_content =
      "Apply the changes requested by the user to the code. Output ONLY the changed code and a brief description of the edits. DO NOT wrap the code in a formatting block. DO NOT provide other text or explanation."
  else
    system_message_content =
      "Apply the changes requested by the user to the code. Output ONLY the changed code. DO NOT wrap the code in a formatting block. DO NOT provide other text or explanation."
  end
  local messages = {
    {
      role = "system",
      content = system_message_content,
    },
    {
      role = "user",
      content = input,
    },
    {
      role = "user",
      content = instructions,
    },
  }
  return messages
end

local namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

local instructions_input, layout, input_window, output_window, output, timer, filetype, bufnr, extmark_id

local display_input_suffix = function(suffix)
  if extmark_id then
    vim.api.nvim_buf_del_extmark(instructions_input.bufnr, namespace_id, extmark_id)
  end

  if not suffix then
    return
  end

  extmark_id = vim.api.nvim_buf_set_extmark(instructions_input.bufnr, namespace_id, 0, -1, {
    virt_text = {
      { Config.options.chat.border_left_sign, "ChatGPTTotalTokensBorder" },
      { "" .. suffix, "ChatGPTTotalTokens" },
      { Config.options.chat.border_right_sign, "ChatGPTTotalTokensBorder" },
      { " ", "" },
    },
    virt_text_pos = "right_align",
  })
end

local spinner = Spinner:new(function(state)
  vim.schedule(function()
    output_window.border:set_text("top", " " .. state .. " ", "center")
    display_input_suffix(state)
  end)
end, {
  text = Config.options.loading_text,
})

local show_progress = function()
  spinner:start()
end

local hide_progress = function()
  spinner:stop()
  display_input_suffix()
  output_window.border:set_text("top", " Result ", "center")
end

local setup_and_mount = vim.schedule_wrap(function(lines, output_lines, ...)
  layout:mount()
  -- set input
  if lines then
    vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
  end

  -- set output
  if output_lines then
    vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, output_lines)
  end

  -- set input and output settings
  for _, window in ipairs({ input_window, output_window }) do
    vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
    vim.api.nvim_win_set_option(window.winid, "number", true)
  end
end)

M.edit_with_instructions = function(output_lines, bufnr, selection, ...)
  if bufnr == nil then
    bufnr = vim.api.nvim_get_current_buf()
  end
  filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  local visual_lines, start_row, start_col, end_row, end_col
  if selection == nil then
    visual_lines, start_row, start_col, end_row, end_col = Utils.get_visual_lines(bufnr)
  else
    visual_lines, start_row, start_col, end_row, end_col = unpack(selection)
  end
  local openai_params = Config.options.openai_edit_params
  local use_functions_for_edits = Config.options.use_openai_functions_for_edits
  local settings_panel = Settings.get_settings_panel("edits", openai_params)
  input_window = Popup(Config.options.popup_window)
  output_window = Popup(Config.options.popup_window)
  instructions_input = ChatInput(Config.options.popup_input, {
    prompt = Config.options.popup_input.prompt,
    on_close = function()
      if timer ~= nil then
        timer:stop()
      end
    end,
    on_submit = vim.schedule_wrap(function(instruction)
      -- clear input
      vim.api.nvim_buf_set_lines(instructions_input.bufnr, 0, -1, false, { "" })
      show_progress()

      local input = table.concat(vim.api.nvim_buf_get_lines(input_window.bufnr, 0, -1, false), "\n")
      local messages = build_edit_messages(input, instruction, use_functions_for_edits)
      local function_params = use_functions_for_edits and EDIT_FUNCTION_ARGUMENTS or {}
      local params = vim.tbl_extend("keep", { messages = messages }, Settings.params, function_params)
      Api.edits(params, function(response, usage)
        hide_progress()
        local nlcount = Utils.count_newlines_at_end(input)
        local output_txt = response
        if use_functions_for_edits then
          output_txt = Utils.match_indentation(input, response.changed_code)
          if response.applied_changes then
            vim.notify(response.applied_changes, vim.log.levels.INFO)
          end
        end
        local output_txt_nlfixed = Utils.replace_newlines_at_end(output_txt, nlcount)
        output = Utils.split_string_by_line(output_txt_nlfixed)

        vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, output)
        if usage then
          display_input_suffix(usage.total_tokens)
        end
      end)
    end),
  })

  layout = Layout(
    {
      relative = "editor",
      position = "50%",
      size = {
        width = Config.options.popup_layout.center.width,
        height = Config.options.popup_layout.center.height,
      },
    },
    Layout.Box({
      Layout.Box({
        Layout.Box(input_window, { grow = 1 }),
        Layout.Box(instructions_input, { size = 3 }),
      }, { dir = "col", size = "50%" }),
      Layout.Box(output_window, { size = "50%" }),
    }, { dir = "row" })
  )

  -- accept output window
  for _, mode in ipairs({ "n", "i" }) do
    instructions_input:map(mode, Config.options.edit_with_instructions.keymaps.accept, function()
      instructions_input.input_props.on_close()
      local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
      vim.api.nvim_buf_set_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, lines)
      vim.notify("Successfully applied the change!", vim.log.levels.INFO)
    end, { noremap = true })
  end

  -- use output as input
  for _, mode in ipairs({ "n", "i" }) do
    instructions_input:map(mode, Config.options.edit_with_instructions.keymaps.use_output_as_input, function()
      local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
      vim.api.nvim_buf_set_lines(input_window.bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, {})
    end, { noremap = true })
  end

  -- close
  for _, mode in ipairs({ "n", "i" }) do
    instructions_input:map(mode, Config.options.edit_with_instructions.keymaps.close, function()
      if vim.fn.mode() == "i" then
        vim.api.nvim_command("stopinsert")
      end
      vim.cmd("q")
    end, { noremap = true })
  end

  -- toggle settings
  local settings_open = false
  for _, popup in ipairs({ settings_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_settings, function()
        if settings_open then
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(input_window, { grow = 1 }),
              Layout.Box(instructions_input, { size = 3 }),
            }, { dir = "col", size = "50%" }),
            Layout.Box(output_window, { size = "50%" }),
          }, { dir = "row" }))
          settings_panel:hide()
          vim.api.nvim_set_current_win(instructions_input.winid)
        else
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(input_window, { grow = 1 }),
              Layout.Box(instructions_input, { size = 3 }),
            }, { dir = "col", grow = 1 }),
            Layout.Box(output_window, { grow = 1 }),
            Layout.Box(settings_panel, { size = 40 }),
          }, { dir = "row" }))
          settings_panel:show()
          settings_panel:mount()

          vim.api.nvim_set_current_win(settings_panel.winid)
          vim.api.nvim_buf_set_option(settings_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(settings_panel.winid, "cursorline", true)
        end
        settings_open = not settings_open
        -- set input and output settings
        --  TODO
        for _, window in ipairs({ input_window, output_window }) do
          vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
          vim.api.nvim_win_set_option(window.winid, "number", true)
        end
      end, {})
    end
  end

  -- cycle windows
  local active_panel = instructions_input
  for _, popup in ipairs({ input_window, output_window, settings_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      if mode == "i" and (popup == input_window or popup == output_window) then
        goto continue
      end
      popup:map(mode, Config.options.edit_with_instructions.keymaps.cycle_windows, function()
        if active_panel == instructions_input then
          vim.api.nvim_set_current_win(input_window.winid)
          active_panel = input_window
          vim.api.nvim_command("stopinsert")
        elseif active_panel == input_window and mode ~= "i" then
          vim.api.nvim_set_current_win(output_window.winid)
          active_panel = output_window
          vim.api.nvim_command("stopinsert")
        elseif active_panel == output_window and mode ~= "i" then
          if settings_open then
            vim.api.nvim_set_current_win(settings_panel.winid)
            active_panel = settings_panel
          else
            vim.api.nvim_set_current_win(instructions_input.winid)
            active_panel = instructions_input
          end
        elseif active_panel == settings_panel then
          vim.api.nvim_set_current_win(instructions_input.winid)
          active_panel = instructions_input
        end
      end, {})
      ::continue::
    end
  end

  -- toggle diff mode
  local diff_mode = Config.options.edit_with_instructions.diff
  for _, popup in ipairs({ settings_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_diff, function()
        diff_mode = not diff_mode
        for _, winid in ipairs({ input_window.winid, output_window.winid }) do
          vim.api.nvim_set_current_win(winid)
          if diff_mode then
            vim.api.nvim_command("diffthis")
          else
            vim.api.nvim_command("diffoff")
          end
          vim.api.nvim_set_current_win(instructions_input.winid)
        end
      end, {})
    end
  end

  setup_and_mount(visual_lines, output_lines)
end

return M
