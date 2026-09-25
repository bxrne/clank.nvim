local M = {}

---@param opts { line1: integer?, line2: integer?, range: integer? }?
---@return table[] quickfix items
function M.get_qf_items(opts)
  opts = opts or {}
  local qf = vim.fn.getqflist()

  if opts.range and opts.range > 0 and vim.bo.buftype == "quickfix" then
    local items = {}
    for i = opts.line1, opts.line2 do
      if qf[i] then
        table.insert(items, qf[i])
      end
    end
    return items
  end

  return qf
end

---@param items table[] quickfix items
---@return table<integer, table[]> items grouped by bufnr
---@return integer[] bufnrs in first-seen order
function M.group_by_bufnr(items)
  local groups = {}
  local order = {}
  for _, item in ipairs(items) do
    if item.bufnr and item.bufnr > 0 then
      if not groups[item.bufnr] then
        groups[item.bufnr] = {}
        table.insert(order, item.bufnr)
      end
      table.insert(groups[item.bufnr], item)
    end
  end
  return groups, order
end

---@param content string current file content
---@param items table[] quickfix items for this file
---@return string
function M.build_prompt(content, items)
  local issues = {}
  for _, item in ipairs(items) do
    table.insert(issues, ("line %d: %s"):format(item.lnum, item.text))
  end

  return "Fix the following issues in this file:\n\n"
    .. table.concat(issues, "\n")
    .. "\n\nReturn the complete corrected file content, with no explanations "
    .. "and no markdown code fences:\n\n"
    .. content
end

---@param bufnr integer
---@param items table[] quickfix items for this buffer
---@param provider_or_cwd clank.Provider|string legacy provider position or cwd
---@param maybe_cwd string? cwd when the legacy (bufnr, items, provider, cwd) form is used
function M.fix_buffer(bufnr, items, provider_or_cwd, maybe_cwd)
  vim.fn.bufload(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local prompt = M.build_prompt(table.concat(lines, "\n"), items)

  local spinner = require("clank.progress").buffer(bufnr, 0, "fixing")

  local config = require("clank").config

  local cwd = maybe_cwd or (type(provider_or_cwd) == "string" and provider_or_cwd) or vim.fn.getcwd()
  local legacy_provider = type(provider_or_cwd) == "table" and provider_or_cwd or nil

  local function on_chunk() end
  local function on_done(result)
    vim.schedule(function()
      spinner.stop()
      local new_lines = vim.split(result.text, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
      vim.notify(("clank: fixed %s"):format(vim.api.nvim_buf_get_name(bufnr)), vim.log.levels.INFO)
    end)
  end
  local function on_error(err)
    vim.schedule(function()
      spinner.stop()
      vim.notify("clank: " .. err, vim.log.levels.ERROR)
    end)
  end

  if legacy_provider then
    legacy_provider.send({ prompt = prompt, model = config.model, cwd = cwd }, {
      on_chunk = on_chunk,
      on_done = on_done,
      on_error = on_error,
    })
    return
  end

  local dispatch = require("clank.dispatch")

  dispatch.send("fix", { prompt = prompt, model = config.model, cwd = cwd }, {
    on_chunk = on_chunk,
    on_done = on_done,
    on_error = on_error,
  })
end

---@param opts { line1: integer?, line2: integer?, range: integer? }?
function M.fix(opts)
  local items = M.get_qf_items(opts)
  if #items == 0 then
    vim.notify("clank: quickfix list is empty", vim.log.levels.INFO)
    return
  end

  local groups, order = M.group_by_bufnr(items)
  if #order == 0 then
    vim.notify("clank: no fixable quickfix entries", vim.log.levels.INFO)
    return
  end

  local cwd = vim.fn.getcwd()

  for _, bufnr in ipairs(order) do
    M.fix_buffer(bufnr, groups[bufnr], cwd)
  end
end

return M
