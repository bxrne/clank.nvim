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

vim.api.nvim_create_user_command("ClankDo", function(opts)
  require("clank.agent").run(opts.args)
end, { nargs = "+" })

vim.api.nvim_create_user_command("ClankPR", function(opts)
  local n = tonumber(opts.args)
  if not n then
    vim.notify("clank: ClankPR requires an integer argument", vim.log.levels.ERROR)
    return
  end
  require("clank.pr").open(n)
end, { nargs = 1 })

vim.api.nvim_create_user_command("ClankPRComment", function()
  require("clank.pr").comment()
end, {})

vim.api.nvim_create_user_command("ClankPRSubmit", function()
  require("clank.pr").submit()
end, {})
