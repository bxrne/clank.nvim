local M = {}

---@class clank.AgentAction
---@field type "command"|"qflist"|"edit"
---@field command string?      command action: ex command without leading colon
---@field action string?       qflist action: "r" to replace, "a" to append
---@field items table[]?       qflist action: quickfix items
---@field path string?         edit action: file path (relative to cwd or absolute)
---@field content string?      edit action: full new contents for the file

---@param user_prompt string
---@return string
function M.build_prompt(user_prompt)
  return table.concat({
    "You are an agent operating inside a Neovim session via the clank.nvim plugin.",
    "The user gives you a task. Explore the repository as needed (read files, run",
    "git, etc.), then respond with a JSON object describing the Neovim actions to",
    "perform. Respond with ONLY the JSON object: no prose, no markdown code fences.",
    "",
    "Schema:",
    '  { "actions": [ <action>, ... ] }',
    "",
    "Each <action> is exactly one of:",
    '  { "type": "command", "command": "<ex command, without the leading colon>" }',
    '  { "type": "qflist", "action": "r"|"a",',
    '    "items": [ { "filename": "<path>", "lnum": <int>, "text": "<message>" } ] }',
    '  { "type": "edit", "path": "<path>", "content": "<full new file contents>" }',
    "",
    'Use qflist action "r" to replace the quickfix list, "a" to append to it.',
    "For edit actions, return the complete new contents of the file, not a diff.",
    "Prefer paths relative to the repository root. Keep the plan minimal.",
    'If there is nothing to do, respond with { "actions": [] }.',
    "",
    "Task:",
    user_prompt,
  }, "\n")
end

---Extract the JSON object from a model response that may be wrapped in prose or
---markdown code fences.
---@param text string
---@return string
function M.extract_json(text)
  local fenced = text:match("```json%s*(.-)%s*```") or text:match("```%s*(.-)%s*```")
  if fenced then
    return vim.trim(fenced)
  end

  local first = text:find("{", 1, true)
  local last = text:reverse():find("}", 1, true)
  if first and last then
    return text:sub(first, #text - last + 1)
  end

  return vim.trim(text)
end

---@param text string
---@return clank.AgentAction[]? actions
---@return string? err
function M.parse_actions(text)
  local body = M.extract_json(text or "")
  if body == "" then
    return nil, "empty response from harness"
  end

  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then
    return nil, "could not parse JSON response: " .. tostring(decoded)
  end

  if type(decoded) ~= "table" or type(decoded.actions) ~= "table" then
    return nil, "response did not contain an 'actions' array"
  end

  return decoded.actions, nil
end

---Human-readable, one-line-per-action summary used for the confirmation prompt.
---@param actions clank.AgentAction[]
---@return string
function M.summarize(actions)
  local lines = {}
  for i, action in ipairs(actions) do
    local desc
    if action.type == "command" then
      desc = ":" .. tostring(action.command)
    elseif action.type == "qflist" then
      local verb = action.action == "a" and "append" or "replace"
      desc = ("quickfix %s (%d item(s))"):format(verb, #(action.items or {}))
    elseif action.type == "edit" then
      desc = "edit " .. tostring(action.path)
    else
      desc = "unknown action (" .. tostring(action.type) .. ")"
    end
    table.insert(lines, ("%d. %s"):format(i, desc))
  end
  return table.concat(lines, "\n")
end

---@param action clank.AgentAction
function M.execute_action(action)
  if type(action) ~= "table" then
    error("action is not a table")
  end

  if action.type == "command" then
    if type(action.command) ~= "string" then
      error("command action is missing a 'command' string")
    end
    vim.cmd(action.command)
  elseif action.type == "qflist" then
    local mode = action.action == "a" and "a" or "r"
    vim.fn.setqflist(action.items or {}, mode)
  elseif action.type == "edit" then
    if type(action.path) ~= "string" then
      error("edit action is missing a 'path' string")
    end
    local bufnr = vim.fn.bufadd(action.path)
    vim.fn.bufload(bufnr)
    local new_lines = vim.split(action.content or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  else
    error("unknown action type: " .. tostring(action.type))
  end
end

---@param actions clank.AgentAction[]
---@param opts { confirm: boolean? }?
function M.apply(actions, opts)
  opts = opts or {}

  if opts.confirm ~= false then
    local prompt = "clank will run:\n\n" .. M.summarize(actions) .. "\n\nProceed?"
    if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
      vim.notify("clank: cancelled", vim.log.levels.INFO)
      return
    end
  end

  local applied = 0
  for _, action in ipairs(actions) do
    local ok, err = pcall(M.execute_action, action)
    if ok then
      applied = applied + 1
    else
      vim.notify(("clank: action failed: %s"):format(err), vim.log.levels.WARN)
    end
  end

  vim.notify(("clank: applied %d/%d action(s)"):format(applied, #actions), vim.log.levels.INFO)
end

---@param user_prompt string
function M.run(user_prompt)
  if not user_prompt or vim.trim(user_prompt) == "" then
    vim.notify("clank: ClankDo requires a prompt", vim.log.levels.ERROR)
    return
  end

  local config = require("clank").config
  local provider = require("clank.provider").get(config.harness)
  local confirm = not (config.agent and config.agent.confirm == false)
  local cwd = vim.fn.getcwd()

  local spinner = require("clank.progress").echo("working")

  provider.send({ prompt = M.build_prompt(user_prompt), cwd = cwd }, {
    on_chunk = function() end,
    on_done = function(result)
      vim.schedule(function()
        spinner.stop()
        local actions, err = M.parse_actions(result.text)
        if err then
          vim.notify("clank: " .. err, vim.log.levels.ERROR)
          return
        end
        if #actions == 0 then
          vim.notify("clank: nothing to do", vim.log.levels.INFO)
          return
        end
        M.apply(actions, { confirm = confirm })
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        spinner.stop()
        vim.notify("clank: " .. err, vim.log.levels.ERROR)
      end)
    end,
  })
end

return M
