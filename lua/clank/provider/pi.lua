local registry = require("clank.provider")

---@class clank.PiProvider: clank.Provider
local M = {
  name = "pi",
  -- Pi exposes 15+ providers and hundreds of models; these are common
  -- defaults, but any non-empty model string is accepted (see is_valid_model).
  models = {
    "claude-opus-5",
    "claude-sonnet-4-6",
    "deepseek-v4-pro",
    "openai/gpt-5",
  },
}

---@return boolean
function M.available()
  return vim.fn.executable("pi") == 1
end

---@param model string
---@return boolean
function M.is_valid_model(model)
  -- Pi accepts bare model names ("claude-opus-5"), "provider/id" patterns, and
  -- model patterns with a ":thinking" suffix, so only reject empty values.
  return type(model) == "string" and vim.trim(model) ~= "" and not model:match("%s")
end

---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(opts, callbacks)
  -- Print mode is Pi's non-interactive one-shot entry point for scripting; it
  -- streams the reply to stdout. Session persistence is file-based via
  -- --session-dir (no resume-by-id flag exists in print mode), so session_id
  -- is intentionally ignored here.
  local cmd = { "pi", "-p", opts.prompt }

  if opts.system then
    vim.list_extend(cmd, { "--system-prompt", opts.system })
  end

  if opts.model then
    vim.list_extend(cmd, { "--model", opts.model })
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
        err = ("pi exited with code %d"):format(result.code)
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

registry.register("pi", M)

return M
