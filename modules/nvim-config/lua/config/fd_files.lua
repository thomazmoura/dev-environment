-- blink.cmp source (the 'fd_files' provider in lua/plugins/completion.lua, markdown only):
-- typing @ then a few letters completes any file under NeoVim's working directory, listed by
-- fd, so "@audioedital" offers "docs/material/audio/resumo - edital 2026.mp3". The matching is
-- fuzzy (letters in order, not a prefix) over the whole relative path, all depths. The source
-- matches with matchfuzzy() itself and returns only the best MAX_ITEMS, because blink caps its
-- menu and would otherwise cut an unfiltered list at whichever files fd printed first.
-- Accepting an item replaces the typed letters with @path, relative to the working directory
-- (@"path" in double quotes when it has a space).
--
-- fd honours .gitignore, so ignored files and .git stay out; hidden files are skipped too.
local KIND_FILE = 17 -- vim.lsp.protocol.CompletionItemKind.File
local MAX_ITEMS = 100
local CACHE_SECONDS = 10

local source = {}
local cache = { cwd = nil, at = 0, paths = {} }

function source.new(opts) return setmetatable({ opts = opts or {} }, { __index = source }) end

--- fd is called fdfind on Debian/Ubuntu
function source.fd() return vim.fn.executable('fd') == 1 and 'fd' or 'fdfind' end

function source:enabled() return vim.bo.filetype == 'markdown' and vim.fn.executable(source.fd()) == 1 end

function source:get_trigger_characters() return { '@' } end

--- Every file under the working directory, all depths, from fd (kept for a few seconds so each
--- keystroke does not rerun it)
local function list_files(callback)
  local cwd = vim.fn.getcwd()
  if cache.cwd == cwd and vim.uv.now() - cache.at < CACHE_SECONDS * 1000 then
    return callback(cache.paths)
  end
  return vim.system(
    { source.fd(), '--type', 'f', '--strip-cwd-prefix', '--color', 'never' },
    { cwd = cwd, text = true },
    vim.schedule_wrap(function(result)
      local paths = vim.split(result.stdout or '', '\n', { trimempty = true })
      table.sort(paths)
      cache = { cwd = cwd, at = vim.uv.now(), paths = paths }
      callback(paths)
    end)
  )
end

--- What is inserted: the path after the @, in double quotes when it has a space
local function insert_text(path)
  return '@' .. (path:find('%s') and ('"' .. path .. '"') or path)
end

function source:get_completions(context, callback)
  local empty = { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  -- "@" at the start of a word (not an e-mail address), followed by the letters typed so far
  local before = context.line:sub(1, context.cursor[2])
  local at = before:find('@[^%s@]*$')
  if not at or (at > 1 and not before:sub(at - 1, at - 1):match('%s')) then
    callback(empty)
    return
  end
  local typed = before:sub(at + 1)

  local line = context.cursor[1] - 1
  local range = {
    start = { line = line, character = at - 1 },
    ['end'] = { line = line, character = context.cursor[2] },
  }
  local job = list_files(function(paths)
    -- Matched here, over the whole relative path, so blink's 200 item cap applies to the best
    -- matches and not to whichever files come first. Every item's filterText is what was
    -- typed, so blink keeps them all, in matchfuzzy's order (sortText)
    local matches = typed == '' and paths or vim.fn.matchfuzzy(paths, typed)
    local items = {}
    for i = 1, math.min(#matches, MAX_ITEMS) do
      items[i] = {
        label = matches[i],
        filterText = typed,
        sortText = string.format('%04d', i),
        kind = KIND_FILE,
        textEdit = { newText = insert_text(matches[i]), range = range },
      }
    end
    -- Incomplete: blink asks again on every keystroke, so the list is matched against the new text
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
  end)
  return function()
    if job then pcall(job.kill, job, 15) end
  end
end

return source
