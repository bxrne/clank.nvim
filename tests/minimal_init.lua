local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({"git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir})
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- Headless test runs spawn many nvim instances in parallel; disable ShaDa so
-- they neither read nor write the user's persistent session state (corrupt
-- ShaDa files otherwise leak E576/E138 errors into test results).
vim.opt.shadafile = "NONE"

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
