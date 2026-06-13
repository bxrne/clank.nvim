vim.api.nvim_create_user_command("ClankFill", function()
  require("clank.fill").fill_selection()
end, { range = true })
