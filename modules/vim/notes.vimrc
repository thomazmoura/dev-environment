" The Notes pane's NeoVim (tmux layout, prefix+n): as bare as nvim -u NORC,
" plus just a few things from the full vimrc -- moving between tmux panes,
" auto-save, a transparent background and markview's markdown rendering -- and
" without a status bar.

" True colors, as in the vimrc, for markview's headings and code blocks
set termguicolors

" No plugins but vim-tmux-navigator, auto-save.nvim and markview.nvim,
" installed by vim-plug for the vimrc.
set noloadplugins
set runtimepath^=~/.local/share/nvim/site/.plugged/vim-tmux-navigator
runtime plugin/tmux_navigator.vim

" Write all buffers before navigating from Vim to tmux pane
let g:tmux_navigator_save_on_switch = 2

" auto-save, as setup.lua has it, and also when the pane loses focus some other
" way than the navigator (a click on another pane, a tmux window switch)
set runtimepath^=~/.local/share/nvim/site/.plugged/auto-save.nvim
lua require("auto-save").setup({ enabled = true, trigger_events = { "BufLeave", "FocusLost" }, execution_message = { message = "" } })
runtime plugin/auto-save.lua

" Long lines wrap at word boundaries instead of splitting a word across lines
set wrap
set linebreak

" .notes is markdown
autocmd BufNewFile,BufRead .notes set filetype=markdown

" Tree-sitter highlighting, as treesitter-settings.lua does (NeoVim ships the
" markdown parsers, so no nvim-treesitter needed)
autocmd FileType markdown lua pcall(vim.treesitter.start)

" Markview (Markdown rendering on normal mode), with the options setup.lua uses
" but for list items not indented at the top level -- bullets and numbers sit
" flush with the left edge -- and by a single space per level of nesting
set runtimepath^=~/.local/share/nvim/site/.plugged/markview.nvim
lua << EOF
-- How many lists <item> sits inside of, not counting its own (0 at the top level)
local function list_depth(buffer, item)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buffer,
    pos = { item.range.row_start, item.range.col_start + item.indent },
  })
  local depth = -1
  while ok and node do
    if node:type() == "list_item" then
      depth = depth + 1
    end
    node = node:parent()
  end
  return math.max(depth, 0)
end

require("markview").setup({
  buf_ignore = {},
  max_length = 99999,
  markdown = {
    list_items = {
      indent_size = 2,
      -- markview pads an item by (ceil(indent / indent_size) + 1) * shift_width
      -- spaces, so no whole shift_width gives 0 at the top level and 1 per
      -- level below it. This fraction makes that product depth + 0.5, which
      -- string.rep truncates to depth.
      shift_width = function(buffer, item)
        local levels = math.ceil(item.indent / 2) + 1
        return (list_depth(buffer, item) + 0.5) / levels
      end,
    },
  },
})
EOF
runtime plugin/markview.lua

" Transparent background
highlight Normal guibg=none ctermbg=none
highlight NormalNC guibg=none ctermbg=none

" No ~ on the empty lines past the end of the buffer
lua vim.opt.fillchars:append({ eob = " " })

" No status bar, nor the ruler that takes its place in the command line
set laststatus=0
set noruler

" No command line either but while typing a command, and none of the messages
" that would pop it up -- "3 lines changed" and the like, the file info on
" opening it, "written" on saving it (auto-save's own message is blanked above)
set cmdheight=0
set report=99999
set shortmess+=FWI

" Ctrl+C on normal mode saves and closes the notes
nnoremap <C-c> <Cmd>wq<CR>
