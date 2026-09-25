local dispatch = require("clank.dispatch")
local registry = require("clank.provider")
local plugin = require("clank")

describe("dispatch", function()
  local orig_system
  local saved_harness
  local saved_commands

  before_each(function()
    orig_system = vim.system
    -- Clear first: tbl_deep_extend never removes keys, so a commands table
    -- left invalid by a previous test would otherwise survive setup().
    plugin.config.commands = {}
    plugin.setup({ harness = "claude", model = "sonnet-4.6", commands = {} })
    saved_harness = plugin.config.harness
    saved_commands = plugin.config.commands
    plugin.config.commands = {}
  end)

  after_each(function()
    vim.system = orig_system
    plugin.config.commands = {}
    plugin.setup({
      harness = "claude",
      model = "sonnet-4.6",
      commands = {},
    })
    plugin.config.harness = saved_harness
    plugin.config.commands = saved_commands
  end)

  it("routes to the provider when no custom command is set", function()
    local seen_opts
    registry.register("fake-dispatch", {
      name = "fake-dispatch",
      send = function(opts, callbacks)
        seen_opts = opts
        callbacks.on_done({ text = "ok" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake-dispatch"

    local done_text
    dispatch.send("fill", { prompt = "hi", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function(result)
        done_text = result.text
      end,
      on_error = function(err)
        error("unexpected error: " .. err)
      end,
    })

    assert.equals("ok", done_text)
    assert.equals("fill", seen_opts.action)
    assert.equals("sonnet-4.6", seen_opts.model)
  end)

  it("routes to the custom command via stdin when commands.<action> is set", function()
    local seen_cmd, seen_opts, on_exit_cb
    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      seen_opts = opts
      on_exit_cb = on_exit
      return { kill = function() end }
    end

    plugin.config.commands = { fill = "mycli --fill" }

    local done_text
    dispatch.send("fill", { prompt = "hi", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function(result)
        done_text = result.text
      end,
      on_error = function(err)
        error("unexpected error: " .. err)
      end,
    })

    assert.equals("mycli --fill", seen_cmd)
    assert.equals("hi", seen_opts.stdin)
    on_exit_cb({ code = 0 })
    assert.equals("", done_text)
  end)

  it("reports invalid custom specs via on_error", function()
    plugin.config.commands = { fill = "" }

    local err_msg
    dispatch.send("fill", { prompt = "hi", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function()
        error("on_done should not be called")
      end,
      on_error = function(err)
        err_msg = err
      end,
    })

    assert.truthy(err_msg:find("commands%.fill", 1))
  end)
end)

describe("custom harness", function()
  local orig_system

  before_each(function()
    orig_system = vim.system
    plugin.config.commands = {}
    plugin.setup({ harness = "custom" })
    plugin.config.commands = {}
  end)

  after_each(function()
    vim.system = orig_system
    plugin.config.commands = {}
    plugin.setup({
      harness = "claude",
      model = "sonnet-4.6",
      commands = {},
    })
    plugin.config.commands = {}
  end)

  it("is registered and accepts any model", function()
    require("clank.provider.custom")
    assert.is_true(plugin.is_valid_harness("custom"))
    assert.is_true(plugin.is_valid_model("anything", "custom"))
  end)

  it("errors when commands.<action> is missing", function()
    local err_msg
    registry.get("custom").send({ prompt = "hi", cwd = "/tmp", action = "fill" }, {
      on_chunk = function() end,
      on_done = function()
        error("on_done should not be called")
      end,
      on_error = function(err)
        err_msg = err
      end,
    })
    assert.truthy(err_msg:find("commands%.fill", 1))
  end)

  it("runs commands.<action> when set", function()
    plugin.config.commands = { ["do"] = { "mycli", "do" } }
    local seen_cmd
    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      on_exit({ code = 0 })
      return { kill = function() end }
    end

    local done = false
    registry.get("custom").send({ prompt = "hi", cwd = "/tmp", action = "do" }, {
      on_chunk = function() end,
      on_done = function()
        done = true
      end,
      on_error = function(err)
        error("unexpected error: " .. err)
      end,
    })
    assert.same({ "mycli", "do" }, seen_cmd)
    assert.is_true(done)
  end)
end)
