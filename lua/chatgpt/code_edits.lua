local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Utils = require("chatgpt.utils")
local Spinner = require("chatgpt.spinner")
local Settings = require("chatgpt.settings")
local Help = require("chatgpt.help")

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
  if extmark_id and input_window.bufnr ~= nil then
    vim.api.nvim_buf_del_extmark(instructions_input.bufnr, namespace_id, extmark_id)
  end

  if not suffix or input_window.bufnr == nil then
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
    if input_window.bufnr ~= nil then
      output_window.border:set_text(
        "top",
        { { " " .. state .. " ", Config.options.highlights.code_edit_result_title } },
        "center"
      )
    end
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

  if output_window.bufnr ~= nil then
    output_window.border:set_text("top", { { " Result ", Config.options.highlights.code_edit_result_title } }, "center")
  end
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
    if Config.options.show_line_numbers ~= false then
      vim.api.nvim_win_set_option(window.winid, "number", true)
    end
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
  local help_panel = Help.get_help_panel("edit") -- I like the highlighting for Lua.
  local open_extra_panels = {} -- tracks which extra panels are open
  local active_panel = instructions_input -- for cycling windows
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
            local applied_changes = response.applied_changes

            -- ChatGPT 4 returns a table of changes, but ChatGPT 3 returns a string.
            -- For ChatGPT 4, format the changes as a bullet list.
            if type(applied_changes) == "table" then
              for i, change in ipairs(applied_changes) do
                applied_changes[i] = " - " .. change
              end
              applied_changes = table.concat(applied_changes, "\n")
            end

            vim.notify(applied_changes, vim.log.levels.INFO)
          end
        end
        local output_txt_nlfixed = Utils.replace_newlines_at_end(output_txt, nlcount)
        output = Utils.split_string_by_line(output_txt_nlfixed)

        if output_window.bufnr ~= nil then
          vim.api.nvim_buf_set_lines(output_window.bufnr, 0, -1, false, output)
        end

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

  -- yank output window
  for _, mode in ipairs({ "n", "i" }) do
    instructions_input:map(mode, Config.options.edit_with_instructions.keymaps.yank, function()
      instructions_input.input_props.on_close()
      local lines = vim.api.nvim_buf_get_lines(output_window.bufnr, 0, -1, false)
      vim.fn.setreg(Config.options.yank_register, lines)
      vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
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
  for _, popup in ipairs({ input_window, output_window, settings_panel, help_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.close, function()
        if vim.fn.mode() == "i" then
          vim.api.nvim_command("stopinsert")
        end
        vim.cmd("q")
      end, { noremap = true })
    end
  end

  local function inTable(tbl, item)
    for key, value in pairs(tbl) do
      if value == item then
        return key
      end
    end
    return false
  end

  -- toggle extra panels
  local function toggle_extra_panel(extra_panel, modifiable_panel)
    local extra_open = inTable(open_extra_panels, extra_panel)
    if not extra_open then
      table.insert(open_extra_panels, extra_panel)
      local extra_boxes = function()
        local box_size = (100 / #open_extra_panels) .. "%"
        local boxes = {}
        for i, panel in ipairs(open_extra_panels) do
          -- for the last panel, make it grow to fill the remaining space
          if i == #open_extra_panels then
            table.insert(boxes, Layout.Box(panel, { grow = 1 }))
          else
            table.insert(boxes, Layout.Box(panel, { size = box_size }))
          end
        end
        return Layout.Box(boxes, { dir = "col", size = 40 })
      end
      layout:update(Layout.Box({
        Layout.Box({
          Layout.Box(input_window, { grow = 1 }),
          Layout.Box(instructions_input, { size = 3 }),
        }, { dir = "col", grow = 1 }),
        Layout.Box(output_window, { grow = 1 }),
        extra_boxes(),
      }, { dir = "row" }))
      extra_panel:show()
      extra_panel:mount()

      vim.api.nvim_set_current_win(extra_panel.winid)
      active_panel = extra_panel
      vim.api.nvim_buf_set_option(extra_panel.bufnr, "modifiable", modifiable_panel)
      vim.api.nvim_win_set_option(extra_panel.winid, "cursorline", true)
    else
      table.remove(open_extra_panels, extra_open)
      if #open_extra_panels == 0 then
        layout:update(Layout.Box({
          Layout.Box({
            Layout.Box(input_window, { grow = 1 }),
            Layout.Box(instructions_input, { size = 3 }),
          }, { dir = "col", size = "50%" }),
          Layout.Box(output_window, { size = "50%" }),
        }, { dir = "row" }))
        extra_panel:hide()
        vim.api.nvim_set_current_win(instructions_input.winid)
        active_panel = instructions_input
      else
        local box_size = (100 / #open_extra_panels) .. "%"
        local extra_boxes = function()
          local boxes = {}
          for _, panel in ipairs(open_extra_panels) do
            table.insert(boxes, Layout.Box(panel, { size = box_size }))
          end
          return Layout.Box(boxes, { dir = "col", size = 40 })
        end
        layout:update(Layout.Box({
          Layout.Box({
            Layout.Box(input_window, { grow = 1 }),
            Layout.Box(instructions_input, { size = 3 }),
          }, { dir = "col", grow = 1 }),
          Layout.Box(output_window, { grow = 1 }),
          extra_boxes(),
        }, { dir = "row" }))
        extra_panel:hide()
        vim.api.nvim_set_current_win(open_extra_panels[#open_extra_panels].winid)
        active_panel = open_extra_panels[#open_extra_panels]
      end
    end
    for _, window in ipairs({ input_window, output_window }) do
      vim.api.nvim_buf_set_option(window.bufnr, "filetype", filetype)
      vim.api.nvim_win_set_option(window.winid, "number", true)
    end
  end

  -- toggle settings
  for _, popup in ipairs({ instructions_input, settings_panel, help_panel }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_settings, function()
        toggle_extra_panel(settings_panel, false)
        -- set input and output settings
        --  TODO
      end, {})
    end
  end

  -- toggle help
  for _, popup in ipairs({ instructions_input, settings_panel, help_panel }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_help, function()
        toggle_extra_panel(help_panel, false)
        -- set input and output settings
        --  TODO
      end, {})
    end
  end

  -- cycle windows
  for _, popup in ipairs({ input_window, output_window, settings_panel, help_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      if not (mode == "i" and (popup == input_window or popup == output_window)) then
        popup:map(mode, Config.options.edit_with_instructions.keymaps.cycle_windows, function()
          -- #352 is a bug where active_panel is something not in here, maybe an
          -- old window or something, lost amongst the global state
          local possible_windows = {
            input_window,
            output_window,
            settings_panel,
            help_panel,
            instructions_input,
            unpack(open_extra_panels),
          }

          -- So if active_panel isn't something we expect it to be, make it do be.
          if not inTable(possible_windows, active_panel) then
            active_panel = instructions_input
          end

          local active_panel_is_in_extra_panels = inTable(open_extra_panels, active_panel)
          if active_panel == instructions_input then
            vim.api.nvim_set_current_win(input_window.winid)
            active_panel = input_window
            vim.api.nvim_command("stopinsert")
          elseif active_panel == input_window and mode ~= "i" then
            vim.api.nvim_set_current_win(output_window.winid)
            active_panel = output_window
            vim.api.nvim_command("stopinsert")
          elseif active_panel == output_window and mode ~= "i" then
            if #open_extra_panels == 0 then
              vim.api.nvim_set_current_win(instructions_input.winid)
              active_panel = instructions_input
            else
              vim.api.nvim_set_current_win(open_extra_panels[1].winid)
              active_panel = open_extra_panels[1]
            end
          elseif active_panel_is_in_extra_panels then
            -- next index with wrap around and 0 for instructions_input
            local next_index = (active_panel_is_in_extra_panels + 1) % (#open_extra_panels + 1)
            if next_index == 0 then
              vim.api.nvim_set_current_win(instructions_input.winid)
              active_panel = instructions_input
            else
              vim.api.nvim_set_current_win(open_extra_panels[next_index].winid)
              active_panel = open_extra_panels[next_index]
            end
          end
        end, {})
      end
    end
  end

  -- toggle diff mode
  local diff_mode = Config.options.edit_with_instructions.diff
  for _, popup in ipairs({ help_panel, settings_panel, instructions_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, Config.options.edit_with_instructions.keymaps.toggle_diff, function()
        diff_mode = not diff_mode
        for _, winid in ipairs({ input_window.winid, output_window.winid }) do
          vim.api.nvim_set_current_win(winid)
          if diff_mode then
            -- set local wrap to be previous option to make it mroe readable(wrap=true is often more readable in diff mode).
            local previous_wrap = vim.o.wrap
            vim.api.nvim_command("diffthis")
            if vim.o.wrap ~= previous_wrap then
              vim.o.wrap = previous_wrap
            end
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
