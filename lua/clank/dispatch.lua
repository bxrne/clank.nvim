---Dispatch a clank action to either a per-action custom command
---(config.commands.<action>) or the configured provider.
local registry = require("clank.provider")
local custom = require("clank.custom")

local M = {}

---@param action string one of "fill"|"review"|"fix"|"do"
---@return string|string[]|nil
function M.command_for(action)
  local ok, clank = pcall(require, "clank")
  if not ok or type(clank.config) ~= "table" then
    return nil
  end
  local commands = clank.config.commands
  if type(commands) ~= "table" then
    return nil
  end
  local spec = commands[action]
  if spec == nil or spec == false then
    return nil
  end
  return spec
end

---@param action string one of "fill"|"review"|"fix"|"do"
---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(action, opts, callbacks)
  local spec = M.command_for(action)
  if spec ~= nil then
    if not custom.is_valid_spec(spec) then
      callbacks.on_error(("clank: invalid commands.%s: expected a non-empty string or argv list"):format(action))
      return { cancel = function() end }
    end
    opts.action = action
    return custom.send(spec, opts, callbacks)
  end

  local config = require("clank").config
  local provider = registry.get(config.harness)
  if opts.model == nil then
    opts.model = config.model
  end
  opts.action = action
  return provider.send(opts, callbacks)
end

return M
