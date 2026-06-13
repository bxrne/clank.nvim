local registry = require("clank.provider")

---@class CustomModule
local M = {}

---@param harness string
---@return boolean
M.is_valid_harness = function(harness)
  local ok, provider = pcall(registry.get, harness)
  if not ok then
    return false
  end
  return provider.available()
end

---@param model string
---@param harness string?
---@return boolean
M.is_valid_model = function(model, harness)
  local ok, provider = pcall(registry.get, harness or "claude")
  if not ok then
    return false
  end
  return provider.is_valid_model(model)
end

return M
