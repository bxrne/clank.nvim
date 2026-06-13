---@class clank.SendOpts
---@field prompt string
---@field system string?
---@field session_id string?
---@field cwd string

---@class clank.SendResult
---@field text string
---@field session_id string?

---@class clank.SendCallbacks
---@field on_chunk fun(text: string)
---@field on_done fun(result: clank.SendResult)
---@field on_error fun(err: string)

---@class clank.JobHandle
---@field cancel fun(self: clank.JobHandle)

---@class clank.Provider
---@field name string
---@field models string[]
---@field send fun(opts: clank.SendOpts, callbacks: clank.SendCallbacks): clank.JobHandle
---@field available fun(): boolean
---@field is_valid_model fun(model: string): boolean

---@class clank.ProviderRegistry
---@field _registry table<string, clank.Provider>
local M = { _registry = {} }

---@param name string
---@param impl clank.Provider
function M.register(name, impl)
  M._registry[name] = impl
end

---@param name string
---@return clank.Provider
function M.get(name)
  local impl = M._registry[name]
  if not impl then
    -- built-in providers self-register on require; load it lazily on first use
    pcall(require, "clank.provider." .. name)
    impl = M._registry[name]
  end
  if not impl then
    error(("clank: unknown provider %q"):format(name))
  end
  return impl
end

return M
