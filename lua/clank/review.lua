local M = {}

---@return boolean
function M.git_available()
  return vim.fn.executable("git") == 1
end

---@param cwd string
---@return boolean
function M.is_git_repo(cwd)
  local result = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, { cwd = cwd, text = true }):wait()
  return result.code == 0
end

---@param n integer 0 = uncommitted changes, 1 = most recent commit, 2 = the one before that, ...
---@param cwd string
---@return string? diff
---@return string? err
function M.get_diff(n, cwd)
  local cmd
  if n == 0 then
    cmd = { "git", "diff", "HEAD" }
  else
    local new_rev = n == 1 and "HEAD" or ("HEAD~%d"):format(n - 1)
    cmd = { "git", "diff", ("HEAD~%d"):format(n), new_rev }
  end

  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "")
  end
  return result.stdout, nil
end

---@param diff string
---@return string
function M.build_prompt(diff)
  return "Review the following git diff. For each issue you find (bugs, "
    .. "style problems, edge cases, etc.), respond with exactly one line in "
    .. "the format `path:line: message`, where `line` is the line number in "
    .. "the new version of the file. Do not wrap the output in markdown code "
    .. "fences, and do not include any other text. If there are no issues, "
    .. "respond with nothing.\n\n"
    .. diff
end

---@param text string
---@return table[] quickfix items
function M.parse_comments(text)
  local items = {}
  for line in vim.gsplit(text, "\n", { plain = true }) do
    local filename, lnum, message = line:match("^(.-):(%d+):%s*(.+)$")
    if filename and lnum and message then
      table.insert(items, {
        filename = vim.trim(filename),
        lnum = tonumber(lnum),
        text = vim.trim(message),
      })
    end
  end
  return items
end

---@param n integer 0 = uncommitted changes, 1 = most recent commit, 2 = the one before that, ...
function M.review(n)
  n = n or 0
  local cwd = vim.fn.getcwd()

  if not M.git_available() then
    vim.notify("clank: git is not available on $PATH", vim.log.levels.ERROR)
    return
  end

  if not M.is_git_repo(cwd) then
    vim.notify("clank: not a git repository", vim.log.levels.ERROR)
    return
  end

  local diff, err = M.get_diff(n, cwd)
  if err then
    vim.notify("clank: " .. err, vim.log.levels.ERROR)
    return
  end

  if vim.trim(diff or "") == "" then
    vim.notify("clank: nothing to review", vim.log.levels.INFO)
    return
  end

  local config = require("clank").config
  local provider = require("clank.provider").get(config.harness)

  provider.send({ prompt = M.build_prompt(diff), cwd = cwd }, {
    on_chunk = function() end,
    on_done = function(result)
      vim.schedule(function()
        local items = M.parse_comments(result.text)
        vim.fn.setqflist(items, "r")
        if #items == 0 then
          vim.notify("clank: review found no issues", vim.log.levels.INFO)
        else
          vim.cmd("copen")
          vim.notify(("clank: review found %d issue(s)"):format(#items), vim.log.levels.INFO)
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        vim.notify("clank: " .. err, vim.log.levels.ERROR)
      end)
    end,
  })
end

return M
