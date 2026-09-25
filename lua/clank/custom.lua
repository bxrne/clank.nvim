---Run a user-supplied shell command for a clank action.
---The prompt (with any system preamble folded in) is piped via stdin and
---stdout is captured as the harness reply, mirroring the provider contract.
local M = {}

---@param opts clank.SendOpts
---@return string
function M.build_input(opts)
  if opts.system then
    return opts.system .. "\n\n" .. opts.prompt
  end
  return opts.prompt
end

---@param spec string|string[]
---@return boolean
function M.is_valid_spec(spec)
  if type(spec) == "string" then
    return vim.trim(spec) ~= ""
  end
  if type(spec) == "table" and #spec > 0 then
    for _, part in ipairs(spec) do
      if type(part) ~= "string" then
        return false
      end
    end
    return true
  end
  return false
end

---@param spec string|string[]
---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(spec, opts, callbacks)
  local input = M.build_input(opts)
  local stdout_chunks = {}
  local stderr_chunks = {}

  local job = vim.system(spec, {
    text = true,
    cwd = opts.cwd,
    stdin = input,
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
        err = ("custom command exited with code %d"):format(result.code)
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

return M
