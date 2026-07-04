local registry = require("clank.provider")

---@class clank.OpencodeProvider: clank.Provider
local M = {
  name = "opencode",
  -- opencode models are addressed as "provider/model"; these are common
  -- defaults, but any "provider/model" string is accepted (see is_valid_model).
  models = {
    "anthropic/claude-sonnet-4-5",
    "anthropic/claude-opus-4-1",
    "anthropic/claude-haiku-4-5",
    "openai/gpt-5",
    "google/gemini-2.5-pro",
  },
}

---@return boolean
function M.available()
  return vim.fn.executable("opencode") == 1
end

---@param model string
---@return boolean
function M.is_valid_model(model)
  for _, v in ipairs(M.models) do
    if v == model then
      return true
    end
  end
  -- opencode accepts any provider/model pair; validate the shape rather than
  -- enumerating every model across every provider.
  return type(model) == "string" and model:match("^[%w._-]+/[%w._:-]+$") ~= nil
end

---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(opts, callbacks)
  -- opencode's `run` subcommand has no system-prompt flag, so fold any system
  -- prompt into the message as a preamble.
  local prompt = opts.prompt
  if opts.system then
    prompt = opts.system .. "\n\n" .. prompt
  end

  local cmd = { "opencode", "run", prompt }

  if opts.session_id then
    vim.list_extend(cmd, { "--session", opts.session_id })
  end

  local stdout_chunks = {}
  local stderr_chunks = {}

  local job = vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
    stdout = function(_, data)
      if data then
        table.insert(stdout_chunks, data)
        callbacks.on_chunk(data)
      end
    end,
    stderr = function(_, data)
      if data then
        table.insert(stderr_chunks, data)
      end
    end,
  }, function(result)
    if result.code ~= 0 then
      local err = table.concat(stderr_chunks)
      if err == "" then
        err = ("opencode exited with code %d"):format(result.code)
      end
      callbacks.on_error(err)
      return
    end

    callbacks.on_done({ text = table.concat(stdout_chunks) })
  end)

  return {
    cancel = function()
      job:kill(15)
    end,
  }
end

registry.register("opencode", M)

return M
