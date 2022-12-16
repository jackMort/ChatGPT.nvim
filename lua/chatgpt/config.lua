-- ASCII-ART credits:
--  https://www.reddit.com/r/ASCII_Archive/comments/iga1d4/your_robot_friend/
WELCOME_MESSAGE = [[
                    _.           ._                    
               _.agjWMb         dMWkpe._               
              'H8888888b,     ,d8888888H'              
               V88888888Wad8beW88888888V               
              ,;88888888888888888888888:.              
    ,ae.,   _aM8888888888888888888888888Me_   ,.ae.    
  ,d88888b,d8888888888888888888888888888888b.d88888b.  
 d888888888888888888888888888888888888888888888888888b 
'V888888888888888888888888888888888888888888888888888V'
  "V88888888888888888888888888888888888888888888888V"  
    88888888WMP^YMW88888888888888888WMP^YMW88888888    
    88888WP'  _,_ "VW888888W8888888V" _,_  'VW88888    
    888888"  dM8Mb '888888' '888888' d888b  "888888    
    88888H  :H888H: H88888   88888H :H888H:  H88888    
    888888b "^YWWP /888888   888888\ YWWP^" d888888    
    88888888be._.ad8888888._.8888888be._.ad88888888    
    WW8888888888888888888888888888888888888888888WW    
     '''"""^^YW8888888W888888888W8888888WY^^"""'''     
    MWbozxae  8888888/  ._____.  \8888888  aexzodWM    
    88888888  8MMHHWW;  8888888  :WWHHMM8  88888888    
    'Y888888b.__       /8888888\       __.d888888Y'    
     "V888888888MHWkjgd888888888bkpajWHM88888888V"     
       '^Y88888888888888888888888888888888888P^'       
          '"^VY8888888888888888888888888YV^"'          
               '""^^^VY888888888VY^^^""'    
 
 
     If you don't ask the right questions,
        you don't get the right answers.
                                      ~ Robert Half
]]

local M = {}
function M.defaults()
  local defaults = {
    welcome_message = WELCOME_MESSAGE,
    loading_text = "loading",
    question_sign = "", -- 🙂
    answer_sign = "ﮧ", -- 🤖
    max_line_length = 120,
    yank_register = "+",
    chat_layout = {
      relative = "editor",
      position = "50%",
      size = {
        height = "80%",
        width = "80%",
      },
    },
    chat_window = {
      filetype = "chatgpt",
      border = {
        highlight = "FloatBorder",
        style = "rounded",
        text = {
          top = " ChatGPT ",
        },
      },
    },
    chat_input = {
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
        winhighlight = "Normal:Normal",
      },
    },
    openai_params = {
      model = "text-davinci-003",
      frequency_penalty = 0,
      presence_penalty = 0,
      max_tokens = 300,
      temperature = 0,
      top_p = 1,
      n = 1,
    },
    keymaps = {
      close = "<C-c>",
      yank_last = "<C-y>",
      scroll_up = "<C-u>",
      scroll_down = "<C-d>",
    },
  }
  return defaults
end

M.options = {}

function M.setup(options)
  options = options or {}
  M.options = vim.tbl_deep_extend("force", {}, M.defaults(), options)
end

return M
