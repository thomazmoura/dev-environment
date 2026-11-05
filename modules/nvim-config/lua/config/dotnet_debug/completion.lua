-- Completion in dap-ui's Watches pane and the dap REPL from Roslyn, as if the
-- expression were typed on a new line after the statement the debugger stopped
-- at: the locals in scope there, then a variable's members after a dot.
-- Registered as blink.cmp's 'dap_roslyn' provider for those buffers in
-- lua/plugins/completion.lua (netcoredbg has no DAP `completions` request).
--
-- The source buffer is never edited: Roslyn alone gets a didChange with the
-- extra line, the completion request, then a didChange taking it out again,
-- one expression at a time.
local source = {}

local TIMEOUT_MS = 3000 -- a request past it is dropped, and Roslyn's text restored
local EMPTY = { is_incomplete_forward = true, is_incomplete_backward = true, items = {} }
local Kind = vim.lsp.protocol.CompletionItemKind

-- Requests run one at a time, since each one changes Roslyn's copy of the file:
-- a request waiting is replaced by a newer one
local busy, waiting
local function run(job)
  if busy then
    if waiting then waiting.drop() end
    waiting = job
    return
  end
  busy = true
  job.start(function()
    busy = false
    local next_job = waiting
    waiting = nil
    if next_job then run(next_job) end
  end)
end

local function session()
  local s = package.loaded['dap'] and require('dap').session()
  if s and s.config and s.config.type == 'coreclr' then return s end
end

-- The C# buffer of the frame the debugger stopped at, with Roslyn attached
local function frame_buffer()
  local frame = session() and session().current_frame
  local path = frame and frame.source and frame.source.path
  if not path then return end
  local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(path))
  if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'roslyn' })[1]
  if client then return bufnr, client, frame end
end

-- Where a new line goes: after the statement (inside its block) the frame's
-- line starts, so a statement over several lines stays whole; after the `{`
-- or before the `}` when stopped on a brace; after the line otherwise
local function insertion_point(bufnr, frame)
  local row = frame.line - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local indent = line:match('^%s*')
  local col = math.max((frame.column or 1) - 1, #indent)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'c_sharp')
  if ok and parser then
    local node = parser:parse()[1]:root():named_descendant_for_range(row, col, row, col)
    while node do
      local parent = node:parent()
      if node:type() == 'block' then
        local sr, sc, er, ec = node:range()
        if sr == row then return { sr, sc + 1 }, indent end
        return { er, ec - 1 }, indent
      elseif parent and parent:type() == 'block' then
        local _, _, er, ec = node:range()
        return { er, ec }, indent
      end
      node = parent
    end
  end
  return { row, #line }, indent
end

local function sync_kind(client)
  local sync = client.server_capabilities.textDocumentSync
  return type(sync) == 'table' and sync.change or sync
end

-- Gives Roslyn the buffer with the expression on a new line at `loc`, sends
-- request(position, reply) at the end of it, and restores Roslyn's copy when the
-- reply comes or TIMEOUT_MS passes, whichever is first. Then settle(result) runs,
-- result nil on an error or a timeout, and the next request may start
local function with_line(loc, finish, request, settle)
  local bufnr, client = loc.bufnr, loc.client
  local enc = client.offset_encoding
  pcall(vim.lsp._changetracking.flush, client, bufnr)
  local uri = vim.uri_from_bufnr(bufnr)
  local version = vim.lsp.util.buf_versions[bufnr] or vim.b[bufnr].changedtick
  local row, col = loc.at[1], loc.at[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local start = { line = row, character = vim.str_utfindex(line, enc, col, false) }
  local typed = loc.indent .. loc.expr
  local inserted = typed .. ';'

  local function change(changes)
    client:notify('textDocument/didChange', { textDocument = { uri = uri, version = version }, contentChanges = changes })
  end
  local function full_text(extra)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if extra then
      lines[row + 1] = line:sub(1, col) .. '\n' .. inserted .. line:sub(col + 1)
    end
    return table.concat(lines, '\n') .. '\n'
  end

  if sync_kind(client) == 1 then
    change({ { text = full_text(true) } })
  else
    change({ { range = { start = start, ['end'] = start }, text = '\n' .. inserted } })
  end

  local restored = false
  local function reply(result)
    if restored then return end
    restored = true
    if sync_kind(client) == 1 then
      change({ { text = full_text(false) } })
    else
      local stop = { line = row + 1, character = vim.str_utfindex(inserted, enc) }
      change({ { range = { start = start, ['end'] = stop }, text = '' } })
    end
    finish()
    settle(result)
  end
  vim.defer_fn(function() reply(nil) end, TIMEOUT_MS)
  request({ line = row + 1, character = vim.str_utfindex(typed, enc) }, function(err, result)
    reply(not err and result or nil)
  end)
end

-- The expression typed so far: the line after the prompt, up to the cursor
local function typed_expression(context)
  local line = context.line:sub(1, context.cursor[2])
  local prompt = vim.bo[context.bufnr].buftype == 'prompt' and vim.fn.prompt_getprompt(context.bufnr) or ''
  if prompt ~= '' and vim.startswith(line, prompt) then line = line:sub(#prompt + 1) end
  return line
end

-- Roslyn's items without their edits: their ranges are in the C# file, and an
-- added `using` has no place in an expression. blink inserts the text over the
-- word at the cursor instead
local function to_items(result, loc)
  local defaults = result.itemDefaults or {}
  local items = {}
  for _, raw in ipairs(result.items or result) do
    raw.data = raw.data or defaults.data
    local text = raw.textEdit and raw.textEdit.newText or raw.textEditText or raw.insertText or raw.label
    local format = raw.insertTextFormat or defaults.insertTextFormat
    if format ~= 2 or not text:find('%$') then
      table.insert(items, {
        label = raw.label,
        labelDetails = raw.labelDetails,
        kind = raw.kind or Kind.Text,
        detail = raw.detail,
        documentation = raw.documentation,
        sortText = raw.sortText,
        filterText = raw.filterText,
        insertText = text,
        insertTextFormat = 1,
        deprecated = raw.deprecated,
        tags = raw.tags,
        dap_roslyn = { raw = raw, loc = loc },
      })
    end
  end
  return items
end

function source.new() return setmetatable({}, { __index = source }) end

function source:enabled() return session() ~= nil end

function source:get_trigger_characters() return { '.' } end

function source:get_completions(context, callback)
  local function empty() callback(EMPTY) end
  local bufnr, client, frame = frame_buffer()
  if not bufnr then return empty() end
  local at, indent = insertion_point(bufnr, frame)
  local loc = { bufnr = bufnr, client = client, at = at, indent = indent, expr = typed_expression(context) }

  local cancelled = false
  run({
    drop = empty,
    start = function(finish)
      if cancelled then
        empty()
        return finish()
      end
      with_line(loc, finish, function(position, reply)
        local trigger = context.trigger.kind == 'trigger_character'
        client:request('textDocument/completion', {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          position = position,
          context = trigger and { triggerKind = 2, triggerCharacter = context.trigger.character } or { triggerKind = 1 },
        }, reply, bufnr)
      end, function(result)
        if cancelled or not result then return empty() end
        callback({
          is_incomplete_forward = result.isIncomplete or false,
          is_incomplete_backward = true,
          items = to_items(result, loc),
        })
      end)
    end,
  })
  return function() cancelled = true end
end

-- Roslyn describes an item from the text it completed in, so it gets the line again
function source:resolve(item, callback)
  local info = item.dap_roslyn
  if not info or not info.loc.client or info.loc.client:is_stopped() then return callback(item) end
  run({
    drop = function() callback(item) end,
    start = function(finish)
      with_line(info.loc, finish, function(_, reply)
        info.loc.client:request('completionItem/resolve', info.raw, reply, info.loc.bufnr)
      end, function(resolved)
        if not resolved then return callback(item) end
        callback(vim.tbl_extend('force', item, {
          detail = resolved.detail or item.detail,
          documentation = resolved.documentation or item.documentation,
        }))
      end)
    end,
  })
end

return source
