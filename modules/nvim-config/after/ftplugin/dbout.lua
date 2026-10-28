-- Absolute line numbers in results, not relative ones (<Leader>L still toggles them)
vim.opt_local.number = true
vim.opt_local.relativenumber = false

-- yic in dadbod's results yanks the whole value under the cursor, line breaks included, not
-- only what its column shows: config/dbout_compact.lua keeps it. Other operators, and results
-- it did not lay out, get dadbod-ui's own ic (the cell as shown)
vim.keymap.set('o', 'ic', function()
  if vim.v.operator == 'y' then
    local dbout = require('config.dbout_compact')
    -- The cursor's display column from the text: virtcol() counts showbreak's cells on a wrap
    local vcol = vim.api.nvim_strwidth(vim.api.nvim_get_current_line():sub(1, vim.fn.col('.') - 1))
    local value = dbout.value_at(0, vim.fn.line('.'), vcol)
    if value then
      value = value:gsub('\r\n', '\n')
      vim.fn.setreg(vim.v.register, value, 'c')
      if vim.v.register == '"' then vim.fn.setreg('0', value, 'c') end
      if vim.fn.strchars(value) >= dbout.SQLCMD_MAX then
        vim.notify(('dadbod: the value may be cut at sqlcmd\'s %d characters'):format(dbout.SQLCMD_MAX),
          vim.log.levels.WARN)
      end
      return '<Esc>'
    end
  end
  return ':call db_ui#dbout#get_cell_value()<CR>'
end, { buffer = true, expr = true, silent = true, desc = 'Cell value' })

-- The header stays at the top while the rows scroll under it (config/dbout_pin.lua)
vim.schedule(require('config.dbout_pin').sync)

-- H and L move to the previous and next cell of the row (config/dbout_move.lua)
for lhs, direction in pairs({ H = -1, L = 1 }) do
  vim.keymap.set('n', lhs, function()
    local count = vim.v.count1
    if not require('config.dbout_move').move(direction, count) then
      vim.cmd.normal({ count .. lhs, bang = true })
    end
  end, { buffer = true, desc = direction < 0 and 'Previous cell' or 'Next cell' })
end
-- J and K move down and up as j and k, so shift can stay held to move between cells
vim.keymap.set('n', 'J', 'j', { buffer = true, desc = 'Cell below' })
vim.keymap.set('n', 'K', 'k', { buffer = true, desc = 'Cell above' })

-- The whole value under the cursor in a popup: JSON and HTML highlighted, HTML in the browser
-- too (config/dbout_cell.lua)
vim.keymap.set('n', '<Leader><CR>', function() require('config.dbout_cell').open() end,
  { buffer = true, desc = 'Show the cell in a popup' })
