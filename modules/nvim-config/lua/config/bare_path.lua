-- blink.cmp's path source, extended to complete paths relative to the buffer's directory
-- without a leading ./ (registered as the 'path' provider in lua/plugins/completion.lua).
-- The built-in source only resolves ./, ../, ~/, $VAR/ and absolute paths, and skips
-- foo/ as a likely URL piece, so typing modules/az completes nothing.
--
-- Here a word with a slash (modules/az) completes from <buffer dir>/modules, in any
-- buffer: a directory that doesn't exist (and/or, a URL) just yields no items. A word
-- without one (mod) completes from the buffer's directory too, except in WORD_ONLY
-- filetypes, where most words are identifiers that would list every matching file.
-- In ROOTED_FILETYPES a leading / means the buffer's directory and a leading !
-- (a negation) is skipped, as .gitignore patterns write them.
local path = require('blink.cmp.sources.path')
local lib = require('blink.cmp.sources.path.lib')

-- Code, where a word without a slash completes only as a word
local WORD_ONLY = {}
for _, ft in ipairs({
  'lua', 'vim', 'python', 'javascript', 'javascriptreact', 'typescript', 'typescriptreact',
  'cs', 'fsharp', 'java', 'kotlin', 'go', 'rust', 'c', 'cpp', 'ps1', 'sh', 'bash', 'zsh',
  'sql', 'css', 'scss', 'html', 'razor', 'vue', 'svelte',
}) do
  WORD_ONLY[ft] = true
end

-- .gitignore, .dockerignore, .prettierignore, .npmignore, .ignore and .rgignore
-- all get the gitignore filetype
local ROOTED_FILETYPES = { gitignore = true }

local source = setmetatable({}, { __index = path })

function source.new(opts) return setmetatable(path.new(opts), { __index = source }) end

--- The directory to list and the name being typed, or nil to leave the word to the built-in source
--- @param opts blink.cmp.PathOpts
--- @param context blink.cmp.Context
--- @return string?, string?
local function bare_dirname(opts, context)
  local word = context.line:sub(1, context.cursor[2]):match('[^%s:*?<>\'"`|\\]*$')
  local filetype = vim.bo[context.bufnr].filetype
  if ROOTED_FILETYPES[filetype] then word = word:gsub('^!', ''):gsub('^/', '') end
  if word == '' or word:match('^[/~$]') or word:match('^%.%.?/') then return nil end
  if WORD_ONLY[filetype] and not word:find('/') then return nil end

  local dir, name = word:match('^(.*)/([^/]*)$')
  if not dir then dir, name = '', word end
  return vim.fn.resolve(opts.get_cwd(context) .. '/' .. dir), name
end

function source:get_completions(context, callback)
  local dirname, name = bare_dirname(self.opts, context)
  if not dirname then return path.get_completions(self, context, callback) end

  -- The built-in ranges start at the line's start when the word has no slash. The scan
  -- fills the items after candidates resolves, so they are only complete once scheduled
  local start = context.cursor[2] - #name
  local done = vim.schedule_wrap(function(response)
    for _, item in ipairs(response and response.items or {}) do
      item.textEdit.range = vim.deepcopy(item.textEdit.range)
      item.textEdit.range.start.character = start
    end
    callback(response)
  end)

  lib
    .candidates(context, dirname, self.opts.show_hidden_files_by_default or name:sub(1, 1) == '.', self.opts)
    :map(function(items) done({ is_incomplete_forward = false, is_incomplete_backward = false, items = items }) end)
    :catch(function() done() end)
end

return source
