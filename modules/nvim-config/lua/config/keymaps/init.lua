-- Keymaps of the terminal NeoVim. Plugin keymaps live in their lua/plugins spec.
local map = vim.keymap.set

require('config.keymaps.common')

-- <Esc> also clears the search highlight and noice's messages
map('n', '<Esc>', function()
  vim.cmd.nohlsearch()
  pcall(vim.cmd, 'Noice dismiss')
end, { desc = 'Clear highlights and messages' })

map('n', '<Leader>q', '<cmd>q<cr>', { desc = 'Quit window' })

-- Quickfix window toggle
map('n', '<Leader>Q', function()
  local open = vim.fn.getqflist({ winid = 0 }).winid ~= 0
  vim.cmd(open and 'cclose' or 'copen')
end, { desc = 'Toggle quickfix list' })

-- Reload the file from disk (after a checkout outside of NeoVim)
map('n', '<Leader>F', '<cmd>w<cr><cmd>e!<cr>', { desc = 'Save and reload file' })

-- Scratch markdown buffer
map('n', '<Leader>N', '<cmd>enew<cr><cmd>set filetype=markdown<cr>', { desc = 'New markdown buffer' })

-- Git (fugitive). Where gitsigns attaches, its own <Leader>Gd/Gb win.
map('n', '<Leader>Gd', '<cmd>Gdiffsplit<cr>', { desc = 'Diff split' })
map('n', '<Leader>Gm', '<cmd>Gvdiffsplit!<cr><C-w>J', { desc = 'Merge (3-way diff)' })
map('n', '<Leader>Gb', '<cmd>Git blame<cr>', { desc = 'Blame' })

-- Comments through NeoVim's own commenting (the engine behind gc):
-- <Leader>c<Space> toggles, <Leader>cc comments, <Leader>cu uncomments
local function comment(action)
  return function()
    local first, last = vim.fn.line('.'), vim.fn.line('.') + vim.v.count1 - 1
    if vim.fn.mode():match('[vV\22]') then
      first, last = vim.fn.line('v'), vim.fn.line('.')
      if first > last then first, last = last, first end
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
    end

    -- toggle_lines comments unless every non-blank line already is one
    local prefix = vim.trim((vim.bo.commentstring:gsub('%%s.*', '')))
    local all_commented = true
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, first - 1, last, false)) do
      if line:match('%S') and not vim.startswith(vim.trim(line), prefix) then
        all_commented = false
        break
      end
    end
    if action == 'toggle' or (action == 'comment') ~= all_commented then
      require('vim._comment').toggle_lines(first, last)
    end
  end
end
map({ 'n', 'x' }, '<Leader>c<Space>', comment('toggle'), { desc = 'Toggle comment' })
map({ 'n', 'x' }, '<Leader>cc', comment('comment'), { desc = 'Comment' })
map({ 'n', 'x' }, '<Leader>cu', comment('uncomment'), { desc = 'Uncomment' })

-- Markdown: markview's split preview. Elsewhere: conceal on/off (config/autocmds.lua).
map('n', '<Leader>mm', function()
  if require('config.autocmds').markview_filetypes[vim.bo.filetype] then
    vim.cmd('Markview splitToggle')
  else
    vim.b.conceal_enabled = not vim.b.conceal_enabled
    require('config.autocmds').apply_conceal()
  end
end, { desc = 'Toggle Markview split / conceal' })
