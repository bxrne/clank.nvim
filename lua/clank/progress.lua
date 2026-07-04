local M = {}

local SPINNER_FRAMES = { ".", "..", "...", "..", "." }
local INTERVAL_MS = 300

local ns = vim.api.nvim_create_namespace("clank.progress")

---Start a repeating timer that advances the spinner frame and calls `render`.
---@param render fun(frame: string)
---@return uv.uv_timer_t
local function start_timer(render)
  local frame = 1
  local timer = assert(vim.uv.new_timer())
  timer:start(
    INTERVAL_MS,
    INTERVAL_MS,
    vim.schedule_wrap(function()
      frame = (frame % #SPINNER_FRAMES) + 1
      render(SPINNER_FRAMES[frame])
    end)
  )
  return timer
end

---Inline spinner rendered as virtual text at the end of `row` in `bufnr`.
---Use this when the work is anchored to a specific buffer/location.
---@param bufnr integer
---@param row integer 0-indexed line the spinner anchors to
---@param label string e.g. "thinking"
---@return { stop: fun() }
function M.buffer(bufnr, row, label)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
    virt_text = { { " clank: " .. label .. SPINNER_FRAMES[1], "Comment" } },
    virt_text_pos = "eol",
  })

  local timer = start_timer(function(frame)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, {
      id = mark_id,
      virt_text = { { " clank: " .. label .. frame, "Comment" } },
      virt_text_pos = "eol",
    })
  end)

  local stopped = false
  return {
    stop = function()
      if stopped then
        return
      end
      stopped = true
      timer:stop()
      timer:close()
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_id)
    end,
  }
end

---Global spinner rendered in the message area. Use this for work that isn't
---tied to one buffer (e.g. reviewing a diff or running an agent plan).
---@param label string e.g. "reviewing"
---@return { stop: fun() }
function M.echo(label)
  local function render(frame)
    vim.api.nvim_echo({ { "clank: " .. label .. frame, "Comment" } }, false, {})
  end
  render(SPINNER_FRAMES[1])

  local timer = start_timer(render)

  local stopped = false
  return {
    stop = function()
      if stopped then
        return
      end
      stopped = true
      timer:stop()
      timer:close()
      vim.api.nvim_echo({ { "" } }, false, {})
    end,
  }
end

return M
