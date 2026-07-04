local fill = require("clank.fill")
local registry = require("clank.provider")
local plugin = require("clank")

describe("get_visual_selection", function()
  it("returns the range covered by the '< and '> marks for a charwise selection", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "local y = 2", "local z = 3" })

    vim.api.nvim_buf_set_mark(bufnr, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(bufnr, ">", 2, 10, {})

    local range = fill.get_visual_selection(bufnr, "v")
    assert.same({ 1, 0, 1, 11 }, range)
  end)

  it("spans multiple lines for a charwise selection", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "local y = 2", "local z = 3" })

    vim.api.nvim_buf_set_mark(bufnr, "<", 1, 6, {})
    vim.api.nvim_buf_set_mark(bufnr, ">", 3, 10, {})

    local range = fill.get_visual_selection(bufnr, "v")
    assert.same({ 0, 6, 2, 11 }, range)
  end)

  it("clamps an end column that extends to end-of-line (e.g. with $)", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "local y = 2" })

    vim.api.nvim_buf_set_mark(bufnr, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(bufnr, ">", 2, vim.v.maxcol, {})

    local range = fill.get_visual_selection(bufnr, "v")
    assert.same({ 0, 0, 1, 11 }, range)
  end)

  it("takes whole lines for a linewise (V) selection", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "local y = 2", "local z = 3" })

    vim.api.nvim_buf_set_mark(bufnr, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(bufnr, ">", 2, vim.v.maxcol, {})

    local range = fill.get_visual_selection(bufnr, "V")
    assert.same({ 0, 0, 1, 11 }, range)
  end)
end)

describe("build_prompt", function()
  it("includes the selected text and asks for a fence-free reply", function()
    local prompt = fill.build_prompt("function foo() end")
    assert.truthy(prompt:find("function foo() end", 1, true))
    assert.truthy(prompt:find("no markdown code fences", 1, true))
  end)
end)

describe("fill_selection", function()
  local original_harness

  before_each(function()
    plugin.setup()
    original_harness = plugin.config.harness
  end)

  after_each(function()
    plugin.config.harness = original_harness
  end)

  it("replaces the given range with the provider's response", function()
    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        callbacks.on_done({ text = "local x = 42" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = nil" })

    fill.fill_selection({ bufnr = bufnr, range = { 0, 0, 0, 13 } })

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == "local x = 42"
    end)

    assert.same({ "local x = 42" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("replaces a multi-line range with a multi-line response", function()
    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        callbacks.on_done({ text = "local a = 1\nlocal b = 2\nlocal c = 3" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- TODO", "-- fill me in" })

    fill.fill_selection({ bufnr = bufnr, range = { 0, 0, 1, #"-- fill me in" } })

    vim.wait(100, function()
      return vim.api.nvim_buf_line_count(bufnr) == 3
    end)

    assert.same({ "local a = 1", "local b = 2", "local c = 3" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("shows a progress extmark while the request is pending, then clears it", function()
    local ns = vim.api.nvim_create_namespace("clank.progress")
    local on_done

    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        on_done = callbacks.on_done
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = nil" })

    fill.fill_selection({ bufnr = bufnr, range = { 0, 0, 0, 13 } })

    assert.equals(1, #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))

    on_done({ text = "local x = 42" })
    vim.wait(100, function()
      return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}) == 0
    end)

    assert.equals(0, #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
  end)

  it("notifies on error without modifying the buffer", function()
    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        callbacks.on_error("boom")
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = nil" })

    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg, _)
      notified = msg
    end

    fill.fill_selection({ bufnr = bufnr, range = { 0, 0, 0, 13 } })

    vim.wait(100, function()
      return notified ~= nil
    end)
    vim.notify = orig_notify

    assert.truthy(notified:find("boom", 1, true))
    assert.same({ "local x = nil" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)
