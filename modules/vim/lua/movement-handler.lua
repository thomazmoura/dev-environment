local function print_movement_content()
  -- Save the current cursor position
  local start_pos = vim.fn.getpos('.')

  -- Wait for a motion
  local _, motion = pcall(vim.fn.getcharstr)

  -- Get the motion's text object
  local text_obj = vim.fn.getcharstr()

  -- Construct the command to yank the text object
  local cmd = 'y' .. motion .. text_obj

  -- Execute the yank command
  vim.cmd('normal! ' .. cmd)

  -- Get the yanked text
  local yanked_text = vim.fn.getreg('"')

  -- Restore cursor position
  vim.fn.setpos('.', start_pos)

  -- Print the yanked text
  print(yanked_text)
end

-- Create a key mapping (for example, using leader key + ;)
vim.keymap.set('n', '<leader>;', print_movement_content, { noremap = true, silent = true })
