-- :Norm {keys} runs :normal over a range, silently
vim.api.nvim_create_user_command('Norm', function(opts)
  vim.cmd(('silent %d,%dnormal %s'):format(opts.line1, opts.line2, opts.args))
end, { nargs = '+', range = true })
