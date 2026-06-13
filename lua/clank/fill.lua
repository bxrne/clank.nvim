local M = {}

local ns = vim.api.nvim_create_namespace("clank.fill")

local SPINNER_FRAMES = { ".", "..", "...", "..", "." }
local SPINNER_INTERVAL_MS = 300

---@param bufnr integer
---@param row integer 0-indexed line
---@return integer
local function line_len(bufnr, row)
  return #(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
end

---@param bufnr integer
---@param mode string? visual mode the selection was made in ("v", "V", "\22"); defaults to vim.fn.visualmode()
---@return integer[] range {start_row, start_col, end_row, end_col}, matching the
---  nvim_buf_get_text/set_text convention: rows are end-inclusive, end_col is
---  exclusive within end_row
function M.get_visual_selection(bufnr, mode)
  mode = mode or vim.fn.visualmode()
  local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")

  local start_row = start_pos[1] - 1
  local end_row = end_pos[1] - 1

  -- linewise selection ('V'): '>' mark's column is v:maxcol, so take whole lines
  if mode == "V" then
    return { start_row, 0, end_row, line_len(bufnr, end_row) }
  end

  local start_col = start_pos[2]
  local end_col = end_pos[2] + 1

  -- charwise selection extending to end of line (e.g. with $) also reports
  -- v:maxcol; clamp to the actual line length
  local len = line_len(bufnr, end_row)
  if end_col > len then
    end_col = len
  end

  return { start_row, start_col, end_row, end_col }
end

---@param selected_text string
---@return string
function M.build_prompt(selected_text)
  return "Fill in the following code block. Return only the replacement code, "
    .. "with no explanations and no markdown code fences:\n\n"
    .. selected_text
end

---@param opts { bufnr: integer?, range: integer[]? }?
function M.fill_selection(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local range = opts.range or M.get_visual_selection(bufnr)

  local config = require("clank").config
  local provider = require("clank.provider").get(config.harness)

  local lines = vim.api.nvim_buf_get_text(bufnr, range[1], range[2], range[3], range[4], {})
  local selected_text = table.concat(lines, "\n")
  local prompt = M.build_prompt(selected_text)

  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, range[1], 0, {
    virt_text = { { " clank: thinking" .. SPINNER_FRAMES[1], "Comment" } },
    virt_text_pos = "eol",
  })

  local frame = 1
  local timer = vim.uv.new_timer()
  timer:start(
    SPINNER_INTERVAL_MS,
    SPINNER_INTERVAL_MS,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      frame = (frame % #SPINNER_FRAMES) + 1
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, range[1], 0, {
        id = mark_id,
        virt_text = { { " clank: thinking" .. SPINNER_FRAMES[frame], "Comment" } },
        virt_text_pos = "eol",
      })
    end)
  )

  local function clear_mark()
    timer:stop()
    timer:close()
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
  end

  provider.send({ prompt = prompt, cwd = vim.fn.getcwd() }, {
    on_chunk = function() end,
    on_done = function(result)
      local new_lines = vim.split(result.text, "\n", { plain = true })
      vim.schedule(function()
        clear_mark()
        vim.cmd("undojoin")
        vim.api.nvim_buf_set_text(bufnr, range[1], range[2], range[3], range[4], new_lines)
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        clear_mark()
        vim.notify("clank: " .. err, vim.log.levels.ERROR)
      end)
    end,
  })
end

return M
