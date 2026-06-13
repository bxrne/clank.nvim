---@class CustomModule
local M = {}

---@param harness string
---@return boolean
M.is_valid_harness = function(harness)
  local valid_harnesses = { "claude" }
  for _, v in ipairs(valid_harnesses) do
    if v == harness then
      return true
    end
  end
  return false
end

---@param model string
---@return boolean
M.is_valid_model = function(model)
  local valid_models = { "sonnet-4.6" }
  -- TODO: Call out to harness to get the valid models for that harness
  for _, v in ipairs(valid_models) do
    if v == model then
      return true
    end
  end
  return false
end

return M
