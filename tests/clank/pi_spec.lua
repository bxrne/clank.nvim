local registry = require("clank.provider")
require("clank.provider.pi")

describe("pi provider", function()
  local pi = registry.get("pi")
  local orig_system

  before_each(function()
    orig_system = vim.system
  end)

  after_each(function()
    vim.system = orig_system
  end)

  it("is registered under its name", function()
    assert.equals("pi", pi.name)
  end)

  it("accepts bare names and provider/id models, rejects empties", function()
    assert.is_true(pi.is_valid_model("claude-opus-5"))
    assert.is_true(pi.is_valid_model("anthropic/claude-opus-5"))
    assert.is_true(pi.is_valid_model("deepseek-v4-pro:max"))
    assert.is_false(pi.is_valid_model(""))
    assert.is_false(pi.is_valid_model("some model"))
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

    pi.send({ prompt = "do the thing", cwd = "/tmp" }, {
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

    assert.same({ "pi", "-p", "do the thing" }, seen_cmd)
    assert.equals("/tmp", seen_opts.cwd)
    assert.same({ "hello ", "world" }, chunks)

    on_exit_cb({ code = 0 })
    assert.equals("hello world", done_result.text)
  end)

  it("passes --system-prompt and --model when provided", function()
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    pi.send({
      prompt = "do the thing",
      system = "be terse",
      model = "claude-opus-5",
      cwd = "/tmp",
    }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "pi",
      "-p",
      "do the thing",
      "--system-prompt",
      "be terse",
      "--model",
      "claude-opus-5",
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

    pi.send({ prompt = "x", cwd = "/tmp" }, {
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

    local handle = pi.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    handle.cancel()
    assert.equals(15, killed_with)
  end)
end)