-- Recorded macros for C#/SQL chores, as registers and <leader>m keymaps.
-- Written in key notation and turned into raw keys by vim.keycode.

local function setreg(register, keys)
  vim.fn.setreg(register, vim.keycode(keys))
end

local sql_column_to_property = '^Wdi]^Pa <Esc>wdi]hPlD'
  .. ':s/numeric/decimal/e<CR>:s/bit/bool/e<CR>:s/nvarchar/string/e<CR>:s/varchar/string/e<CR>'
  .. ':s/float/double/e<CR>:s/datetime2/datetime/e<CR>:s/bigint/float/e<CR>:s/text/string/e<CR>'
  .. ':s/datetime/DateTime/e<CR>A { get; set; }<Esc>Ipublic <Esc>j'

-- @s: SQL column to C# property
setreg('s', sql_column_to_property)
-- @c: merge SQL mapping and C# properties
setreg('c', '^d2Wf{hDIbuilder.Property(pe<BS><BS>usuario => usuario.<Esc>A)<Esc>o.HasColumnName();<Esc>'
  .. 'hi""<Esc>mz}j^yi]dd`z^f""0pj')
-- @z: turn a constructor parameter into an injected readonly field
setreg('z', '"zyiwb"x y<Esc>"xyiwOprivate readonly <Esc>"xpa <Esc>"zpbi_<Esc>A;<Esc>/{<CR>%O<Esc>'
  .. '"zpI_<Esc>A = <Esc>"zpA;<Esc>==')

local map = vim.keymap.set

-- Runs keys the way @= would: remappable, and [count] times
local function macro(keys)
  return function()
    vim.api.nvim_feedkeys(string.rep(vim.keycode(keys), vim.v.count1), 'mt', false)
  end
end

-- C# - Class/interface boilerplate from the file path (N/I: file-scoped to block namespace)
local namespace = 'inamespace <Esc>"=fnamemodify(expand("%"), ":~:.")<CR>pyiW$F/D:s/\\//./g<CR>A;<Esc>o<Esc>o<Esc>'
local body = '<C-R>0<Esc>F/ldBf.Do{<Esc>o}<Esc>'
local to_block = 'gg$xji{<Esc>Go}<Esc>>i{jo'
map('n', '<leader>mn', namespace .. 'ipublic class ' .. body .. 'O', { desc = 'C#: class' })
map('n', '<leader>mN', namespace .. 'ipublic class ' .. body .. to_block, { desc = 'C#: class (block namespace)' })
map('n', '<leader>mi', namespace .. 'ipublic interface ' .. body .. 'O', { desc = 'C#: interface' })
map('n', '<leader>mI', namespace .. 'ipublic interface ' .. body .. to_block, { desc = 'C#: interface (block namespace)' })

-- C# - Add parameter injection (P: generic type)
local inject = '?(<CR>Oprivate readonly <Esc>"xpa <Esc>"zpbi_<Esc>A;<Esc>/{<CR>%O<Esc>"zpI_<Esc>A = <Esc>"zpA;<Esc>==:noh<CR>'
map('n', '<leader>mp', macro('"zyiwb"xyiw' .. inject), { desc = 'C#: inject parameter' })
map('n', '<leader>mP', macro('"zyiwbva>ob"xyE' .. inject), { desc = 'C#: inject generic parameter' })

-- C# - SQL column to property / merge SQL mapping and properties (take a count)
map('n', '<leader>ms', macro(sql_column_to_property), { desc = 'C#: SQL column to property' })
map('n', '<leader>mc', macro('^d2Wf{hDIbuilder.Property(<Esc>"0pa => <Esc>"0pa.<Esc>A)<Esc>o.HasColumnName();<Esc>'
  .. 'hi""<Esc>mz}j^"zyi]dd`z^f""0"zpj'), { desc = 'C#: merge SQL mapping' })

-- C# - Global usings: paste and sort (U: from the alternate buffer, and save all)
local sort_usings = ':g/^$/d<CR>:g/^using/normal Iglobal <CR>:sort u<CR>'
map('n', '<leader>mu', macro('Gp' .. sort_usings), { desc = 'C#: sort global usings' })
map('n', '<leader>mU', macro(':b#<CR>ggdap:b#<CR>Gp' .. sort_usings .. ':b#<CR>:wa<CR>'), { desc = 'C#: move usings to global' })

-- C# - Make a method async with a CancellationToken (T: after other parameters)
map('n', '<leader>mt', '^Wyiwciwasync Task<lt><C-R>0><Esc>f(%iCancellationToken cancellationToken<Esc>', { desc = 'C#: async + token' })
map('n', '<leader>mT', '^Wyiwciwasync Task<lt><C-R>0><Esc>f(%i, CancellationToken cancellationToken<Esc>', { desc = 'C#: async + token (append)' })
