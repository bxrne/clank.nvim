-- main module file
local module = require("clank.module")

---@class ClankKeymaps
---@field fill string|false

---@class ClankAgentConfig
---@field confirm boolean

---@class ClankCommands
---@field fill string|string[]|false|nil custom shell command for :ClankFill (prompt via stdin)
---@field review string|string[]|false|nil custom shell command for :ClankReview (prompt via stdin)
---@field fix string|string[]|false|nil custom shell command for :ClankFix (prompt via stdin)
---@field do string|string[]|false|nil custom shell command for :ClankDo (prompt via stdin)

---@class ClankCodexConfig
---@field sandbox string sandbox policy: "read-only"|"workspace-write"|"danger-full-access"
---@field yolo boolean bypass approvals and sandbox (adds --dangerously-bypass-approvals-and-sandbox)
---@field skip_git_repo_check boolean pass --skip-git-repo-check (default true)
---@field extra_args string[] extra argv appended to `codex exec`

---@class Config
---@field harness string
---@field model string
---@field keymaps ClankKeymaps
---@field agent ClankAgentConfig
---@field commands ClankCommands
---@field codex ClankCodexConfig
local config = {
  harness = "claude",
  model = "sonnet-4.6",
  keymaps = {
    fill = "<leader>af",
  },
  agent = {
    confirm = true,
  },
  commands = {},
  codex = {
    sandbox = "workspace-write",
    yolo = false,
    skip_git_repo_check = true,
    extra_args = {},
  },
}

---@class MyModule
local M = {}

---@type Config
M.config = config

---@param args Config?
-- you can define your setup function here. Usually configurations can be merged, accepting outside params and
-- you can also put some vialidation here for those.
M.setup = function(args)
  -- Merge into a candidate first so failed validation does not leave
  -- M.config mutated with invalid values.
  local merged = vim.tbl_deep_extend("force", M.config, args or {})
  -- check if the harness is valid
  if not module.is_valid_harness(merged.harness) then
    error("Invalid harness: " .. merged.harness)
  end
  -- with harness="custom" the model is ignored: each action runs its own
  -- commands.<action> shell command, so skip model validation.
  if merged.harness ~= "custom" then
    if not module.is_valid_model(merged.model, merged.harness) then
      error("Invalid model: " .. merged.model)
    end
  end
  module.validate_commands(merged.commands)
  module.validate_codex(merged.codex)

  M.config = merged

  if M.config.keymaps.fill then
    vim.keymap.set("v", M.config.keymaps.fill, function()
      require("clank.fill").fill_selection()
    end, { desc = "Clank: fill selection" })
  end
end

M.is_valid_harness = function(harness)
  return module.is_valid_harness(harness)
end

M.is_valid_model = function(model, harness)
  return module.is_valid_model(model, harness or M.config.harness)
end

return M
