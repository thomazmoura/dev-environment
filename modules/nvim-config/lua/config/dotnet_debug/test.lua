-- <Leader>dt (config/dotnet_debug): debugs the test method under the cursor, or
-- every test of the class under it, through Roslyn's textDocument/runTests,
-- the request behind VS Code's "Debug Test": the server builds the project,
-- finds the tests in the range and runs them with vstest. With attachDebugger
-- it sends workspace/attachDebugger { processId } for the test host, which
-- attach_debugger answers only once nvim-dap is attached and its breakpoints
-- are set. lua/plugins/lsp.lua routes that request, and the $/progress of our
-- tokens, here.
local M = {}

local TITLE = '.NET test'

-- xUnit, NUnit and MSTest, without namespace or "Attribute" suffix
local TEST_ATTRIBUTES = {
  Fact = true, Theory = true, Test = true, TestCase = true, TestCaseSource = true,
  TestMethod = true, DataTestMethod = true,
}

local flash_ns = vim.api.nvim_create_namespace('dotnet_debug_test_flash')
local runs = {} -- partialResultToken -> run
local next_token = 0

local function notify(msg, level, run)
  local record = vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE, replace = run and run.notification })
  if run then run.notification = record end
end

local function is_test_method(node, buf)
  for child in node:iter_children() do
    if child:type() == 'attribute_list' then
      for attribute in child:iter_children() do
        local name = attribute:type() == 'attribute' and attribute:field('name')[1]
        if name then
          local text = vim.treesitter.get_node_text(name, buf):match('([%w_]+)%s*$') or ''
          if TEST_ATTRIBUTES[(text:gsub('Attribute$', ''))] then return true end
        end
      end
    end
  end
  return false
end

-- The node to run at pos ({row, col}, 0-based): the enclosing test method, or
-- else the innermost class/record, and 'method'/'class'. Roslyn decides
-- which tests the range holds.
function M._range(buf, pos)
  local parser = vim.treesitter.get_parser(buf, 'c_sharp', { error = false })
  if not parser then return nil, 'no c_sharp tree-sitter parser' end
  parser:parse(true)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = pos, ignore_injections = true })
  local class
  while node do
    local kind = node:type()
    if kind == 'method_declaration' and is_test_method(node, buf) then return node, 'method' end
    if not class and (kind == 'class_declaration' or kind == 'record_declaration') then class = node end
    node = node:parent()
  end
  if class then return class, 'class' end
  return nil, 'put the cursor in a test method or a test class'
end

local function lsp_position(buf, row, col, encoding)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  return { line = row, character = vim.str_utfindex(line, encoding, math.min(col, #line), false) }
end

local function record(run, value)
  if type(value) ~= 'table' then return end
  if type(value.message) == 'string' and value.message ~= '' then
    vim.list_extend(run.output, vim.split(value.message, '\n'))
  end
  if type(value.progress) == 'table' then run.progress = value.progress end
  if type(value.stage) == 'string' and value.stage ~= run.stage then
    run.stage = value.stage -- "Building project...", "Debugging tests..."
    notify(run.title .. ': ' .. value.stage, vim.log.levels.INFO, run)
  end
end

local function record_all(run, values)
  if type(values) ~= 'table' then return end
  if not vim.islist(values) then values = { values } end
  for _, value in ipairs(values) do record(run, value) end
end

-- $/progress from Roslyn: true when the token is one of ours
function M.progress(params)
  local run = runs[params.token]
  if not run then return false end
  record_all(run, params.value)
  return true
end

local function show_output(run)
  local name = 'dotnet-test://output'
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = 'hide'
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, run.output)
  vim.bo[buf].modifiable = false
  if vim.fn.bufwinid(buf) == -1 then
    vim.cmd('botright 15split')
    vim.api.nvim_win_set_buf(0, buf)
  end
  vim.api.nvim_win_set_cursor(vim.fn.bufwinid(buf), { math.max(1, #run.output), 0 })
end

local function finish(run, err, result)
  runs[run.token] = nil
  if err then
    table.insert(run.output, 'Error: ' .. (err.message or vim.inspect(err)))
    notify(run.title .. ': ' .. (err.message or 'failed'), vim.log.levels.ERROR, run)
    return show_output(run)
  end
  record_all(run, result)
  local progress = run.progress
  if not progress or (progress.totalTests or 0) == 0 then
    notify(run.title .. ': no tests ran', vim.log.levels.WARN, run)
    return show_output(run)
  end
  local failed = progress.testsFailed or 0
  notify(string.format('%s: %d passed, %d failed, %d skipped of %d', run.title, progress.testsPassed or 0,
    failed, progress.testsSkipped or 0, progress.totalTests), failed > 0 and vim.log.levels.WARN or nil, run)
  if failed > 0 then show_output(run) end
end

-- Runs the tests at pos under the debugger; false (and a message) when there
-- is nothing to run there
function M.debug(buf, pos)
  local client = vim.lsp.get_clients({ bufnr = buf, name = 'roslyn' })[1]
  if not client then
    notify('Roslyn is not attached to this buffer', vim.log.levels.WARN)
    return false
  end
  local node, kind = M._range(buf, pos)
  if not node then
    notify(kind, vim.log.levels.WARN)
    return false
  end

  local sr, sc, er, ec = node:range()
  vim.hl.range(buf, flash_ns, 'IncSearch', { sr, sc }, { er, ec }, { timeout = 300 })
  require('config.dotnet_debug.project').save_buffers()

  local name = node:field('name')[1]
  next_token = next_token + 1
  local run = {
    token = 'dotnet-test-' .. next_token,
    title = (name and vim.treesitter.get_node_text(name, buf) or kind) .. (kind == 'class' and ' (class)' or ''),
    output = {},
  }
  runs[run.token] = run
  notify(run.title .. ': building…', vim.log.levels.INFO, run)

  local encoding = client.offset_encoding
  client:request('textDocument/runTests', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    range = { start = lsp_position(buf, sr, sc, encoding), ['end'] = lsp_position(buf, er, ec, encoding) },
    attachDebugger = true,
    partialResultToken = run.token,
  }, function(err, result) finish(run, err, result) end, buf)
  return true
end

-- workspace/attachDebugger: attach nvim-dap to the test host and answer once
-- its configuration (breakpoints) is done, or it failed. Server requests run
-- in a coroutine (vim/lsp/rpc.lua), so this yields until then.
function M.attach_debugger(_, params)
  local dap = require('dap')
  local co = coroutine.running()
  local key = 'dotnet_debug_test'
  local done, timer = false, vim.uv.new_timer()

  local function resolve(attached)
    if done then return end
    done = true
    dap.listeners.after.configurationDone[key] = nil
    dap.listeners.after.attach[key] = nil
    dap.listeners.after.event_terminated[key] = nil
    timer:stop()
    timer:close()
    if co then vim.schedule(function() coroutine.resume(co, attached) end) end
  end
  dap.listeners.after.configurationDone[key] = function() resolve(true) end
  dap.listeners.after.attach[key] = function(_, err) if err then resolve(false) end end
  dap.listeners.after.event_terminated[key] = function() resolve(false) end
  timer:start(60000, 0, function() resolve(false) end)

  local ok, err = pcall(dap.run, {
    type = 'coreclr',
    request = 'attach',
    name = 'Debug tests',
    processId = params.processId,
  })
  if not ok then
    notify('Could not attach to the test host: ' .. tostring(err), vim.log.levels.ERROR)
    co = nil -- answered right here, nothing to resume
    resolve(false)
    return { didAttach = false }
  end
  -- Without a coroutine to wait in, the attach is under way at least
  if not co then return { didAttach = true } end
  return { didAttach = coroutine.yield() }
end

return M
