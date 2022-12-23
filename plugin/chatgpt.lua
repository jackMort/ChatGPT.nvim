vim.api.nvim_create_user_command("ChatGPT", function()
  require("chatgpt").openChat()
end, {})

vim.api.nvim_create_user_command("ChatGPTActAs", function()
  require("chatgpt").selectAwesomePrompt()
end, {})

vim.api.nvim_create_user_command("ChatGPTEditWithInstructions", function()
  require("chatgpt").edit_with_instructions()
end, {})

vim.api.nvim_create_user_command("ChatGPTRun", function(opts)
  require("chatgpt").run_action(opts)
end, {
  nargs = "*",
  range = true,
  complete = function(arg, cmd_line)
    local match = {
      "add_tests",
      "docstring",
      "fix_bugs",
      "grammar_correction",
      "optimize_code",
      "summarize",
      "translate",
    }
    return match
  end,
})
