-- Where the Postgres statements of a text start and end, for <Leader>r in sql buffers
-- (config/sql_statement.lua). Cut the way psql cuts what it sends (its psqlscan.l): at a ';'
-- outside strings, quoted names, comments, $$ bodies and parentheses, and outside the
-- BEGIN ... END of a BEGIN ATOMIC body, which psql tracks by counting BEGIN and CASE after
-- a statement's first word against END. Postgres ends every statement with a ';', so this
-- is all the syntax there is to it, and a query being written doesn't hide the others.
local M = {}

local IDENT_START = '[%a_\128-\255]'
local IDENT_CONT = '^[%w_$\128-\255]*'

--- {start, end} pairs, 0-based UTF-8 byte offsets with the end excluded, leading and
--- trailing whitespace and comments left out
function M.split(text)
  local statements = {}
  local first, last -- 1-based bytes of the statement's first token and its last one's end
  local parens, begins, words = 0, 0, 0
  local i, n = 1, #text

  local function finish()
    if first then table.insert(statements, { first - 1, last }) end
    first, parens, begins, words = nil, 0, 0, 0
  end

  while i <= n do
    local c = text:sub(i, i)
    local start = i
    if c:match('%s') then
      i = text:find('[^%s]', i) or n + 1
      goto continue
    elseif text:sub(i, i + 1) == '--' then
      i = (text:find('\n', i, true) or n) + 1
      goto continue
    elseif text:sub(i, i + 1) == '/*' then
      -- Nested, unlike SQL Server's
      local depth = 0
      repeat
        local open, close = text:find('/*', i, true), text:find('*/', i, true)
        if not close then i = n + 1 break end
        if open and open < close then
          depth, i = depth + 1, open + 2
        else
          depth, i = depth - 1, close + 2
        end
      until depth == 0
      goto continue
    end

    first = first or start
    if c == "'" or c == '"' then
      -- 'it''s', "a ""name""", and E'it\'s' (its E is the word just before)
      local escapes = c == "'" and text:sub(i - 1, i - 1):match('[eE]') and not text:sub(i - 2, i - 2):match('[%w_$\128-\255]')
      i = i + 1
      while i <= n do
        local ch = text:sub(i, i)
        if escapes and ch == '\\' then
          i = i + 2
        elseif ch == c then
          if text:sub(i + 1, i + 1) ~= c then break end
          i = i + 2
        else
          i = i + 1
        end
      end
      i = i + 1
    elseif c == '$' and (text:match('^%$%$', i) or text:match('^%$' .. IDENT_START .. '[%w_\128-\255]*%$', i)) then
      -- $$ ... $$ and $tag$ ... $tag$, not $1
      local tag = text:match('^%$[^$]*%$', i)
      local close = text:find(tag, i + #tag, true)
      i = close and close + #tag or n + 1
    elseif c:match(IDENT_START) then
      local word = text:match('^' .. IDENT_START .. IDENT_CONT:sub(2), i):lower()
      i = i + #word
      words = words + 1
      if word == 'begin' or word == 'case' then
        if words > 1 then begins = begins + 1 end
      elseif word == 'end' and begins > 0 then
        begins = begins - 1
      end
    elseif c == '(' then
      parens, i = parens + 1, i + 1
    elseif c == ')' then
      parens, i = math.max(parens - 1, 0), i + 1
    elseif c == ';' then
      i = i + 1
      if parens == 0 and begins == 0 then
        last = i - 1
        finish()
        goto continue
      end
    else
      i = i + 1
    end
    last = math.min(i, n + 1) - 1

    ::continue::
  end
  finish()
  return statements
end

return M
