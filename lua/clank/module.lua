local registry = require("clank.provider")

---@class CustomModule
local M = {}

---@param harness string
---@return boolean
M.is_valid_harness = function(harness)
  local ok, _ = pcall(registry.get, harness)
  return ok
end

---@param model string
---@param harness string?
---@return boolean
M.is_valid_model = function(model, harness)
  -- the custom harness runs user-supplied shell commands; any model is
  -- accepted (and ignored).
  if harness == "custom" then
    return true
  end
  local ok, provider = pcall(registry.get, harness or "claude")
  if not ok then
    return false
  end
  return provider.is_valid_model(model)
end

local VALID_ACTIONS = { "fill", "review", "fix", "do" }

---@param commands table?
M.validate_commands = function(commands)
  if commands == nil then
    return
  end
  if type(commands) ~= "table" then
    error("Invalid commands: expected a table")
  end
  for action, spec in pairs(commands) do
    local known = false
    for _, valid in ipairs(VALID_ACTIONS) do
      if action == valid then
        known = true
        break
      end
    end
    if not known then
      error("Invalid commands." .. tostring(action) .. ": expected one of fill, review, fix, do")
    end
    if spec ~= nil and spec ~= false and not require("clank.custom").is_valid_spec(spec) then
      error("Invalid commands." .. tostring(action) .. ": expected a non-empty string or argv list")
    end
  end
end

local VALID_SANDBOXES = {
  ["read-only"] = true,
  ["workspace-write"] = true,
  ["danger-full-access"] = true,
}

---@param cfg table?
M.validate_codex = function(cfg)
  if cfg == nil then
    return
  end
  if type(cfg) ~= "table" then
    error("Invalid codex config: expected a table")
  end
  if cfg.sandbox ~= nil and not VALID_SANDBOXES[cfg.sandbox] then
    error("Invalid codex.sandbox: " .. tostring(cfg.sandbox))
  end
  if cfg.extra_args ~= nil then
    if type(cfg.extra_args) ~= "table" then
      error("Invalid codex.extra_args: expected a list of strings")
    end
    for _, part in ipairs(cfg.extra_args) do
      if type(part) ~= "string" then
        error("Invalid codex.extra_args: expected a list of strings")
      end
    end
  end
end

return M
