-- main module file
local module = require("clank.module")

---@class ClankKeymaps
---@field fill string|false

---@class ClankAgentConfig
---@field confirm boolean

---@class Config
---@field harness string
---@field model string
---@field keymaps ClankKeymaps
---@field agent ClankAgentConfig
local config = {
  harness = "claude",
  model = "sonnet-4.6",
  keymaps = {
    fill = "<leader>af",
  },
  agent = {
    confirm = true,
  },
}

---@class MyModule
local M = {}

---@type Config
M.config = config

---@param args Config?
-- you can define your setup function here. Usually configurations can be merged, accepting outside params and
-- you can also put some vialidation here for those.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
  -- check if the harness is valid
  if not module.is_valid_harness(M.config.harness) then
    error("Invalid harness: " .. M.config.harness)
  end
  if not module.is_valid_model(M.config.model, M.config.harness) then
    error("Invalid model: " .. M.config.model)
  end

  if M.config.keymaps.fill then
    vim.keymap.set("v", M.config.keymaps.fill, function()
      require("clank.fill").fill_selection()
    end, { desc = "Clank: fill selection" })
  end
end

M.is_valid_harness = function(harness)
  return module.is_valid_harness(harness)
end

M.is_valid_model = function(model, harness)
  return module.is_valid_model(model, harness or M.config.harness)
end

return M
