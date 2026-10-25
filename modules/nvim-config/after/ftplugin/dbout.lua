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
