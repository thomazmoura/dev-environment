-- The Notes pane's NeoVim (tmux layout, prefix+n): `nvim -u ~/.config/nvim/notes.lua`.
-- As bare as `nvim -u NORC`, plus a few things from the full config -- moving
-- between tmux panes, auto-save, a transparent background and markview's
-- markdown rendering -- and without a status bar.

-- No plugins but these three, from the full config's lazy.nvim install
vim.o.loadplugins = false
local function add(plugin)
  local dir = vim.fn.stdpath('data') .. '/lazy/' .. plugin
  if not vim.uv.fs_stat(dir) then return false end
  vim.opt.rtp:prepend(dir)
  return true
end

-- True colours, for markview's headings and code blocks
vim.o.termguicolors = true

-- Moving to other tmux panes, writing every buffer first
vim.g.tmux_navigator_save_on_switch = 2
if add('vim-tmux-navigator') then vim.cmd.runtime('plugin/tmux_navigator.vim') end

-- Auto-save, as the full config has it, and also when the pane loses focus
-- some other way than the navigator (a click on another pane, a tmux window
-- switch)
if add('auto-save.nvim') then
  require('auto-save').setup({
    enabled = true,
    trigger_events = { 'BufLeave', 'FocusLost' },
    execution_message = { message = '' },
  })
  vim.cmd.runtime('plugin/auto-save.lua')
end

-- Long lines wrap at word boundaries
vim.o.wrap = true
vim.o.linebreak = true

-- .notes is markdown, highlighted by tree-sitter (NeoVim ships the markdown
-- parsers, so no nvim-treesitter needed)
vim.filetype.add({ filename = { ['.notes'] = 'markdown' } })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function() pcall(vim.treesitter.start) end,
})

-- Markview, with the full config's options but for list items: not indented
-- at the top level -- bullets and numbers sit flush with the left edge -- and
-- by a single space per level of nesting
if add('markview.nvim') then
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
  vim.cmd.runtime('plugin/markview.lua')
end

-- Transparent background
vim.cmd('highlight Normal guibg=none ctermbg=none')
vim.cmd('highlight NormalNC guibg=none ctermbg=none')

-- No ~ on the empty lines past the end of the buffer
vim.opt.fillchars:append({ eob = ' ' })

-- No status bar, nor the ruler that takes its place in the command line
vim.o.laststatus = 0
vim.o.ruler = false

-- No command line either but while typing a command, and none of the messages
-- that would pop it up -- "3 lines changed" and the like, the file info on
-- opening it, "written" on saving it (auto-save's own message is blanked above)
vim.o.cmdheight = 0
vim.o.report = 99999
vim.opt.shortmess:append('FWI')

-- Ctrl+C in normal mode saves and closes the notes
vim.keymap.set('n', '<C-c>', '<Cmd>wq<CR>')
