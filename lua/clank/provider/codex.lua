local registry = require("clank.provider")

---@class clank.CodexProvider: clank.Provider
local M = {
  name = "codex",
  -- Common defaults. Any non-empty single-token string is accepted
  -- (see is_valid_model) so new GPT/Codex model names keep working
  -- without a plugin update.
  models = {
    "gpt-5.6",
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5",
    "gpt-4.1",
    "codex-mini-latest",
    "o4-mini",
  },
}

---@return boolean
function M.available()
  return vim.fn.executable("codex") == 1
end

---@param model string
---@return boolean
function M.is_valid_model(model)
  return type(model) == "string" and vim.trim(model) ~= "" and not model:match("%s")
end

---@return { sandbox: string?, yolo: boolean?, skip_git_repo_check: boolean?, extra_args: string[]? }
local function codex_config()
  local ok, clank = pcall(require, "clank")
  if not ok or type(clank.config) ~= "table" then
    return {}
  end
  local cfg = clank.config.codex
  if type(cfg) ~= "table" then
    return {}
  end
  return cfg
end

---@param opts clank.SendOpts
---@param callbacks clank.SendCallbacks
---@return clank.JobHandle
function M.send(opts, callbacks)
  local cfg = codex_config()

  -- codex exec has no system-prompt flag, so fold any system
  -- prompt into the message as a preamble.
  local prompt = opts.prompt
  if opts.system then
    prompt = opts.system .. "\n\n" .. prompt
  end

  local cmd = { "codex", "exec", prompt }

  local yolo = cfg.yolo == true
  if yolo then
    vim.list_extend(cmd, { "--dangerously-bypass-approvals-and-sandbox" })
  else
    local sandbox = cfg.sandbox or "workspace-write"
    if sandbox and sandbox ~= "" then
      vim.list_extend(cmd, { "--sandbox", sandbox })
    end
  end

  if cfg.skip_git_repo_check ~= false then
    vim.list_extend(cmd, { "--skip-git-repo-check" })
  end

  if opts.model then
    vim.list_extend(cmd, { "--model", opts.model })
  end

  if type(cfg.extra_args) == "table" then
    vim.list_extend(cmd, cfg.extra_args)
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
        err = ("codex exited with code %d"):format(result.code)
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

registry.register("codex", M)

return M
