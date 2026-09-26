-- The Workhorse VS Code extension, on the same keys as workhorse.nvim
local vscode = require('vscode')

local function call(lhs, command, args, desc)
  vim.keymap.set('n', lhs, function() vscode.call(command, { args = args }) end, { desc = desc })
end

local queries = {
  wT = '0ce03ce4-34b3-417b-a7d7-928d45a970dc', -- Tree
  wt = 'a7977848-adab-4453-a4cf-39c28163ac3c', -- Tree
  wu = '729b31ef-3bce-4fcb-b300-0342e4ce69c8', -- User Stories
  wf = '38cfedab-c989-41bb-9d28-71d2c4ad9464', -- Features
  we = '7c0761cd-ba78-4769-a28e-68685934d0aa', -- Epics
  wl = 'd53e77f7-d7c8-49ff-ba14-35a061d047e9', -- LuaLine
  wa = '3c82101c-2a67-408f-9fd7-8ad00a55710c', -- Full (All)
  wx = '9a90e30d-0827-4fe9-9426-e70a8fd62ca6', -- Trash
}
for lhs, id in pairs(queries) do
  call('<Leader>' .. lhs, 'workhorse.openQuery', { id }, 'Workhorse query')
end

call('<Leader>wq', 'workhorse.pickQuery', nil, 'Workhorse: pick query')
call('<Leader>wr', 'workhorse.refresh', nil, 'Workhorse: refresh')
call('<Leader>ws', 'workhorse.changeState', nil, 'Workhorse: change state')
call('<Leader>wR', 'workhorse.resume', nil, 'Workhorse: resume last query')
call('<Leader>wi', 'workhorse.openInBrowser', nil, 'Workhorse: open in browser')
call('<Leader>wD', 'workhorse.openDescription', nil, 'Workhorse: open description')
