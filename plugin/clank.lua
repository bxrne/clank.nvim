vim.api.nvim_create_user_command("ClankFill", function()
  require("clank.fill").fill_selection()
end, { range = true })

vim.api.nvim_create_user_command("ClankFix", function(opts)
  require("clank.fix").fix({ line1 = opts.line1, line2 = opts.line2, range = opts.range })
end, { range = true })

vim.api.nvim_create_user_command("ClankReview", function(opts)
  local n = tonumber(opts.args)
  if not n then
    vim.notify("clank: ClankReview requires an integer argument", vim.log.levels.ERROR)
    return
  end
  require("clank.review").review(n)
end, { nargs = 1 })
