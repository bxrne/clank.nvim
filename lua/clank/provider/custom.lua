local registry = require("clank.provider")
local custom = require("clank.custom")
local dispatch = require("clank.dispatch")

---@class clank.CustomProvider: clank.Provider
local M = {
  name = "custom",
  models = {},
}

---@return boolean
function M.available()
  return true
end

---@param model string?
---@return boolean
function M.is_valid_model(model)
  -- The model is ignored: each action runs its own shell command.
  return true
end

---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(opts, callbacks)
  local action = opts.action
  if type(action) ~= "string" then
    callbacks.on_error("clank: custom harness requires an action (fill|review|fix|do)")
    return { cancel = function() end }
  end
  local spec = dispatch.command_for(action)
  if spec == nil then
    callbacks.on_error(("clank: commands.%s is not set"):format(action))
    return { cancel = function() end }
  end
  if not custom.is_valid_spec(spec) then
    callbacks.on_error(("clank: invalid commands.%s: expected a non-empty string or argv list"):format(action))
    return { cancel = function() end }
  end
  return custom.send(spec, opts, callbacks)
end

registry.register("custom", M)

return M
