local fix = require("clank.fix")
local registry = require("clank.provider")
local plugin = require("clank")

describe("build_prompt", function()
  it("lists each issue and includes the file content", function()
    local prompt = fix.build_prompt("local x = 1", {
      { lnum = 1, text = "use a better name" },
      { lnum = 2, text = "missing return" },
    })

    assert.truthy(prompt:find("line 1: use a better name", 1, true))
    assert.truthy(prompt:find("line 2: missing return", 1, true))
    assert.truthy(prompt:find("local x = 1", 1, true))
    assert.truthy(prompt:find("no markdown code fences", 1, true))
  end)
end)

describe("get_qf_items", function()
  before_each(function()
    local bufnr1 = vim.api.nvim_create_buf(false, true)
    local bufnr2 = vim.api.nvim_create_buf(false, true)
    vim.fn.setqflist({
      { bufnr = bufnr1, lnum = 1, text = "issue 1" },
      { bufnr = bufnr1, lnum = 2, text = "issue 2" },
      { bufnr = bufnr2, lnum = 3, text = "issue 3" },
    }, "r")
  end)

  after_each(function()
    vim.fn.setqflist({}, "r")
  end)

  it("returns all items when there is no range", function()
    local items = fix.get_qf_items()
    assert.equals(3, #items)
  end)

  it("returns all items when not called from the quickfix window", function()
    local items = fix.get_qf_items({ line1 = 1, line2 = 1, range = 1 })
    assert.equals(3, #items)
  end)
end)

describe("group_by_bufnr", function()
  it("groups items by bufnr, preserving first-seen order", function()
    local groups, order = fix.group_by_bufnr({
      { bufnr = 2, lnum = 1, text = "a" },
      { bufnr = 1, lnum = 2, text = "b" },
      { bufnr = 2, lnum = 3, text = "c" },
    })

    assert.same({ 2, 1 }, order)
    assert.equals(2, #groups[2])
    assert.equals(1, #groups[1])
  end)

  it("ignores items without a valid bufnr", function()
    local groups, order = fix.group_by_bufnr({
      { bufnr = 0, lnum = 1, text = "a" },
    })

    assert.same({}, order)
    assert.same({}, groups)
  end)
end)

describe("fix", function()
  local original_harness
  local orig_notify

  before_each(function()
    plugin.setup()
    original_harness = plugin.config.harness
    orig_notify = vim.notify
  end)

  after_each(function()
    plugin.config.harness = original_harness
    vim.notify = orig_notify
    vim.fn.setqflist({}, "r")
  end)

  it("notifies when the quickfix list is empty", function()
    vim.fn.setqflist({}, "r")

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    fix.fix()

    assert.truthy(notified:find("quickfix list is empty", 1, true))
  end)

  it("sends the buffer content and applies the provider's response", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1", "return x" })

    vim.fn.setqflist({
      { bufnr = bufnr, lnum = 1, text = "use a better name" },
    }, "r")

    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        callbacks.on_done({ text = "local count = 1\nreturn count" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    fix.fix()

    vim.wait(100, function()
      return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == "local count = 1"
    end)

    assert.same({ "local count = 1", "return count" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)
