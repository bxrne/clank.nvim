local registry = require("clank.provider")
require("clank.provider.claude")

describe("provider registry", function()
  it("returns a registered provider", function()
    local provider = registry.get("claude")
    assert.equals("claude", provider.name)
  end)

  it("errors for an unknown provider", function()
    assert.has_error(function()
      registry.get("does-not-exist")
    end)
  end)

  it("allows registering a new provider", function()
    local fake = { name = "fake" }
    registry.register("fake", fake)
    assert.equals(fake, registry.get("fake"))
  end)
end)

describe("claude provider", function()
  local claude = registry.get("claude")
  local orig_system

  before_each(function()
    orig_system = vim.system
  end)

  after_each(function()
    vim.system = orig_system
  end)

  it("builds the expected command and reports success", function()
    local seen_cmd, seen_opts, on_exit_cb

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      seen_opts = opts
      on_exit_cb = on_exit

      opts.stdout(nil, "hello ")
      opts.stdout(nil, "world")

      return {
        kill = function() end,
      }
    end

    local chunks = {}
    local done_result

    claude.send({ prompt = "do the thing", cwd = "/tmp" }, {
      on_chunk = function(text)
        table.insert(chunks, text)
      end,
      on_done = function(result)
        done_result = result
      end,
      on_error = function(err)
        error("unexpected error: " .. err)
      end,
    })

    assert.same({ "claude", "-p", "do the thing", "--output-format", "text" }, seen_cmd)
    assert.equals("/tmp", seen_opts.cwd)
    assert.same({ "hello ", "world" }, chunks)

    on_exit_cb({ code = 0 })
    assert.equals("hello world", done_result.text)
  end)

  it("includes --system-prompt and --resume when provided", function()
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    claude.send({
      prompt = "do the thing",
      system = "be terse",
      session_id = "abc123",
      cwd = "/tmp",
    }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "claude",
      "-p",
      "do the thing",
      "--output-format",
      "text",
      "--system-prompt",
      "be terse",
      "--resume",
      "abc123",
    }, seen_cmd)
  end)

  it("reports failure via on_error", function()
    local on_exit_cb

    vim.system = function(cmd, opts, on_exit)
      on_exit_cb = on_exit
      opts.stderr(nil, "boom")
      return {
        kill = function() end,
      }
    end

    local err_msg

    claude.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function()
        error("on_done should not be called")
      end,
      on_error = function(err)
        err_msg = err
      end,
    })

    on_exit_cb({ code = 1 })
    assert.equals("boom", err_msg)
  end)

  it("returns a handle that can be cancelled", function()
    local killed_with

    vim.system = function(cmd, opts, on_exit)
      return {
        kill = function(_, signal)
          killed_with = signal
        end,
      }
    end

    local handle = claude.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    handle.cancel()
    assert.equals(15, killed_with)
  end)
end)
