local registry = require("clank.provider")

---@class clank.ClaudeProvider: clank.Provider
local M = {
  name = "claude",
}

---@return boolean
function M.available()
  return vim.fn.executable("claude") == 1
end

---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(opts, callbacks)
  local cmd = { "claude", "-p", opts.prompt, "--output-format", "text" }

  if opts.system then
    vim.list_extend(cmd, { "--system-prompt", opts.system })
  end

  if opts.session_id then
    vim.list_extend(cmd, { "--resume", opts.session_id })
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
        err = ("claude exited with code %d"):format(result.code)
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

registry.register("claude", M)

return M
