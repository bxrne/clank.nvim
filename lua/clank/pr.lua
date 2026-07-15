local M = {}

---@return boolean
function M.git_available()
  return vim.fn.executable("git") == 1
end

---@return boolean
function M.gh_available()
  return vim.fn.executable("gh") == 1
end

---@param cwd string
---@return boolean
function M.is_git_repo(cwd)
  local result = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, { cwd = cwd, text = true }):wait()
  return result.code == 0
end

---@param cwd string
---@param n integer
---@return string
function M.worktree_path(cwd, n)
  local parent = vim.fn.fnamemodify(cwd, ":h")
  local name = vim.fn.fnamemodify(cwd, ":t")
  return parent .. "/" .. name .. "-pr-" .. n
end

---@param n integer
---@return string
function M.branch_name(n)
  return "clank-pr-" .. n
end

---@param n integer
---@param cwd string
---@return boolean ok
---@return string? err
function M.fetch_pr_ref(n, cwd)
  local branch = M.branch_name(n)
  local result = vim
    .system({ "git", "fetch", "origin", ("pull/%d/head:%s"):format(n, branch) }, { cwd = cwd, text = true })
    :wait()
  if result.code ~= 0 then
    return false, vim.trim(result.stderr or "")
  end
  return true, nil
end

---@param cwd string
---@param path string
---@param branch string
---@return boolean ok
---@return string? err
function M.add_worktree(cwd, path, branch)
  local result = vim.system({ "git", "worktree", "add", path, branch }, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return false, vim.trim(result.stderr or "")
  end
  return true, nil
end

---@param n integer PR number
function M.open(n)
  local cwd = vim.fn.getcwd()

  if not M.git_available() then
    vim.notify("clank: git is not available on $PATH", vim.log.levels.ERROR)
    return
  end

  if not M.gh_available() then
    vim.notify("clank: gh is not available on $PATH", vim.log.levels.ERROR)
    return
  end

  if not M.is_git_repo(cwd) then
    vim.notify("clank: not a git repository", vim.log.levels.ERROR)
    return
  end

  local path = M.worktree_path(cwd, n)
  local branch = M.branch_name(n)

  if vim.fn.isdirectory(path) == 0 then
    local ok, err = M.fetch_pr_ref(n, cwd)
    if not ok then
      vim.notify("clank: " .. err, vim.log.levels.ERROR)
      return
    end

    ok, err = M.add_worktree(cwd, path, branch)
    if not ok then
      vim.notify("clank: " .. err, vim.log.levels.ERROR)
      return
    end
  end

  vim.cmd.tcd(path)
  vim.notify(("clank: opened PR #%d at %s"):format(n, path), vim.log.levels.INFO)

  local items, err = M.get_comments(n, path)
  if not items then
    vim.notify("clank: could not load PR comments: " .. (err or "unknown error"), vim.log.levels.WARN)
    return
  end

  vim.fn.setqflist(items, "r")
  if #items > 0 then
    vim.cmd("copen")
    vim.notify(("clank: loaded %d PR comment(s)"):format(#items), vim.log.levels.INFO)
  end
end

---Existing GitHub review comments (line-anchored) on a PR.
---@param n integer
---@param cwd string
---@return table[]? items quickfix items
---@return string? err
function M.get_comments(n, cwd)
  local result = vim
    .system({ "gh", "api", ("repos/{owner}/{repo}/pulls/%d/comments"):format(n) }, { cwd = cwd, text = true })
    :wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "")
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or type(data) ~= "table" then
    return nil, "could not parse PR comments"
  end

  local items = {}
  for _, c in ipairs(data) do
    local lnum = c.line or c.original_line
    if lnum and c.path then
      table.insert(items, {
        filename = c.path,
        lnum = lnum,
        text = ("%s: %s"):format((c.user or {}).login or "?", (c.body or ""):gsub("\r?\n", " ")),
      })
    end
  end
  return items, nil
end

---Extract the PR number from a `:ClankPR` worktree path (`<repo>-pr-<n>`).
---@param cwd string
---@return integer? n
function M.pr_number_from_cwd(cwd)
  local name = vim.fn.fnamemodify(cwd, ":t")
  return tonumber(name:match("%-pr%-(%d+)$"))
end

---@type table<integer, { path: string, line: integer, body: string }[]>
M.drafts = {}

---@param n integer
---@param path string
---@param line integer
---@param body string
function M.add_comment(n, path, line, body)
  M.drafts[n] = M.drafts[n] or {}
  table.insert(M.drafts[n], { path = path, line = line, body = body })
end

---Open a floating scratch buffer to draft a review comment on the current line.
---Queues the comment locally; it is only sent to GitHub by `:ClankPRSubmit`.
function M.comment()
  local cwd = vim.fn.getcwd()
  local n = M.pr_number_from_cwd(cwd)
  if not n then
    vim.notify("clank: not inside a :ClankPR worktree", vim.log.levels.ERROR)
    return
  end

  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(72, vim.o.columns - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = 4,
    style = "minimal",
    border = "rounded",
    title = ("clank: comment on %s:%d (<CR> save, q cancel)"):format(path, line),
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = vim.trim(table.concat(lines, "\n"))
    close()
    if body == "" then
      vim.notify("clank: empty comment discarded", vim.log.levels.INFO)
      return
    end
    M.add_comment(n, path, line, body)
    vim.notify(("clank: queued comment on %s:%d (%d queued)"):format(path, line, #M.drafts[n]), vim.log.levels.INFO)
  end, { buffer = buf })

  vim.keymap.set("n", "q", close, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf })

  vim.cmd.startinsert()
end

---@param cwd string
---@return string? sha
---@return string? err
function M.get_head_sha(cwd)
  local result = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "")
  end
  return vim.trim(result.stdout or ""), nil
end

---@param n integer
---@param cwd string
---@param event "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
---@param body string
---@return boolean ok
---@return string? err
function M.submit_review(n, cwd, event, body)
  local sha, err = M.get_head_sha(cwd)
  if not sha then
    return false, err
  end

  local comments = {}
  for _, draft in ipairs(M.drafts[n] or {}) do
    table.insert(comments, { path = draft.path, line = draft.line, body = draft.body })
  end

  local payload = vim.json.encode({
    commit_id = sha,
    body = body,
    event = event,
    comments = comments,
  })

  local result = vim
    .system(
      { "gh", "api", "-X", "POST", ("repos/{owner}/{repo}/pulls/%d/reviews"):format(n), "--input", "-" },
      { cwd = cwd, text = true, stdin = payload }
    )
    :wait()

  if result.code ~= 0 then
    return false, vim.trim(result.stderr or "")
  end

  M.drafts[n] = nil
  return true, nil
end

local EVENTS = {
  { label = "Approve", event = "APPROVE" },
  { label = "Request changes", event = "REQUEST_CHANGES" },
  { label = "Comment", event = "COMMENT" },
}

---Interactively pick a verdict and submit any queued comments as one PR review.
---Works regardless of the PR's status (open, closed, or merged).
function M.submit()
  local cwd = vim.fn.getcwd()
  local n = M.pr_number_from_cwd(cwd)
  if not n then
    vim.notify("clank: not inside a :ClankPR worktree", vim.log.levels.ERROR)
    return
  end

  vim.ui.select(EVENTS, {
    prompt = "clank: submit PR review as",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end

    local drafts = M.drafts[n] or {}
    local needs_body = choice.event ~= "APPROVE" and #drafts == 0

    vim.ui.input({ prompt = "clank: review summary (optional): " }, function(input)
      local body = input or ""
      if needs_body and vim.trim(body) == "" then
        vim.notify("clank: a summary is required to submit with no line comments", vim.log.levels.ERROR)
        return
      end

      local ok, submit_err = M.submit_review(n, cwd, choice.event, body)
      if not ok then
        vim.notify("clank: " .. submit_err, vim.log.levels.ERROR)
        return
      end
      vim.notify(("clank: submitted review (%s) on PR #%d"):format(choice.label, n), vim.log.levels.INFO)
    end)
  end)
end

return M
