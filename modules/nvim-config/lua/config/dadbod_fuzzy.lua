-- vim-dadbod-completion's blink source, extended to let blink filter fuzzily (registered as
-- the 'dadbod' provider in lua/plugins/completion.lua). The built-in source passes the word
-- being typed to vim_dadbod_completion#omni, which keeps only the names starting with it,
-- and asks again on every keystroke, so blink never sees divergencia in RegistroDeDivergencia.
--
-- Here omni gets MATCH_ALL as its base and returns everything for the context (the tables,
-- the columns of the table before a dot, aliases), which blink caches for the word and
-- filters itself. Raise g:vim_dadbod_completion_source_limits with it (lua/plugins/database.lua):
-- omni keeps only the first 200 of each list.
local dadbod = require('vim_dadbod_completion.blink')

-- omni splices its base into a regex ('^' . base), and an empty one returns nothing
-- outside a trigger character
local MATCH_ALL = '.*'

-- The built-in source's mapping from omni's kinds to LSP ones
local KINDS = {
  F = 3, -- Function -> Function
  C = 5, -- Column -> Field
  A = 6, -- Alias -> Variable
  T = 7, -- Table -> Class
  R = 14, -- Reserved -> Keyword
  S = 19, -- Schema -> Folder
}

local source = setmetatable({}, { __index = dadbod })

function source.new() return setmetatable({}, { __index = source }) end

function source:get_completions(context, callback)
  local items, seen = {}, {}
  for _, item in ipairs(vim.fn['vim_dadbod_completion#omni'](0, MATCH_ALL) or {}) do
    local key = item.word .. item.kind
    if not seen[key] then
      seen[key] = true
      table.insert(items, {
        label = item.abbr or item.word,
        insertText = item.word,
        labelDetails = item.menu and { description = item.menu } or nil,
        documentation = item.info or '',
        kind = KINDS[item.kind] or vim.lsp.protocol.CompletionItemKind.Text,
      })
    end
  end

  callback({ context = context, is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return source
