WELCOME_MESSAGE = [[
 
     If you don't ask the right questions,
        you don't get the right answers.
                                      ~ Robert Half
]]

function default_quickfix_cmd()
  if pcall(require, "trouble") then
    return "Trouble quickfix"
  else
    return "cope"
  end
end

local M = {}
function M.defaults()
  local defaults = {
    api_key_cmd = nil,
    yank_register = "+",
    extra_curl_params = nil,
    show_line_numbers = true,
    edit_with_instructions = {
      diff = false,
      keymaps = {
        close = "<C-c>",
        close_n = "<Esc>",
        accept = "<C-y>",
        yank = "<C-u>",
        toggle_diff = "<C-d>",
        toggle_settings = "<C-o>",
        toggle_help = "<C-h>",
        cycle_windows = "<Tab>",
        use_output_as_input = "<C-i>",
      },
    },
    chat = {
      welcome_message = WELCOME_MESSAGE,
      default_system_message = "",
      loading_text = "Loading, please wait ...",
      show_hints = true,
      question_sign = "", -- 🙂
      answer_sign = "ﮧ", -- 🤖
      border_left_sign = "",
      border_right_sign = "",
      max_line_length = 120,
      sessions_window = {
        active_sign = "● ",
        inactive_sign = "○ ",
        current_line_sign = "▸ ",
        border = {
          style = "rounded",
          text = {
            top = " Sessions ",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
      },
      keymaps = {
        close = "q",
        close_n = nil,
        yank_last = "Y",
        scroll_up = "<C-u>",
        scroll_down = "<C-d>",
        new_session = "gn",
        cycle_windows = "<Tab>",
        cycle_modes = "gl",
        next_message = "]m",
        prev_message = "[m",
        next_code_block = "]c",
        prev_code_block = "[c",
        select_session = "<CR>",
        rename_session = "r",
        delete_session = "d",
        draft_message = "gd",
        edit_message = "e",
        delete_message = "d",
        toggle_settings = "gs",
        toggle_sessions = "gp",
        toggle_help = "gh",
        toggle_message_role = "gm",
        toggle_system_role_open = "gr",
        stop_generating = "<C-c>",
        yank_code = "y",
        toggle_fold = "za",
      },
    },
    popup_layout = {
      default = "center",
      center = {
        width = "80%",
        height = "80%",
      },
      right = {
        width = "30%",
        width_settings_open = "50%",
      },
    },
    popup_window = {
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top = " ChatGPT ",
        },
      },
      win_options = {
        wrap = true,
        linebreak = true,
        foldcolumn = "1",
        foldmethod = "manual",
        foldenable = true,
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
      buf_options = {
        filetype = "markdown",
      },
    },
    system_window = {
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top = " SYSTEM ",
        },
      },
      win_options = {
        wrap = true,
        linebreak = true,
        foldcolumn = "2",
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    popup_input = {
      prompt = "  ",
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top_align = "center",
          top = " Prompt ",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
      submit = "<C-Enter>",
      submit_n = "<Enter>",
      max_visible_lines = 20,
      placeholder = "Ask anything... (Ctrl+Enter to send)",
    },
    settings_window = {
      setting_sign = "  ",
      border = {
        style = "rounded",
        text = {
          top = " Settings ",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    help_window = {
      setting_sign = "  ",
      border = {
        style = "rounded",
        text = {
          top = " Help ",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      },
    },
    openai_params = {
      model = "gpt-5-mini",
    },
    openai_edit_params = {
      model = "gpt-5-mini",
    },
    context = {
      lsp = {
        enabled = true,
        max_lines = 50,
      },
      project = {
        enabled = true,
        auto_detect = true,
        context_files = {
          ".chatgpt.md",
          ".cursorrules",
          ".github/copilot-instructions.md",
        },
      },
    },
    ignore_default_actions_path = false,
    actions_paths = {},
    show_quickfixes_cmd = default_quickfix_cmd(),
    predefined_chat_gpt_prompts = "https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv",
    highlights = {
      help_key = "@symbol",
      help_description = "@comment",
      params_value = "Identifier",
      input_title = "FloatBorder",
      active_session = "ErrorMsg",
      code_edit_result_title = "FloatBorder",
    },
  }
  return defaults
end

M.options = {}

M.namespace_id = vim.api.nvim_create_namespace("ChatGPTNS")

function M.setup(options)
  options = options or {}
  M.options = vim.tbl_deep_extend("force", {}, M.defaults(), options)
end

return M
