local registry = require("clank.provider")
require("clank.provider.opencode2")

describe("opencode2 provider", function()
  local opencode2 = registry.get("opencode2")
  local orig_system

  before_each(function()
    orig_system = vim.system
  end)

  after_each(function()
    vim.system = orig_system
  end)

  it("is registered under its name", function()
    assert.equals("opencode2", opencode2.name)
  end)

  it("accepts listed, provider/model, and variant-suffixed models", function()
    assert.is_true(opencode2.is_valid_model("anthropic/claude-sonnet-4-5"))
    assert.is_true(opencode2.is_valid_model("someprovider/some-model"))
    assert.is_true(opencode2.is_valid_model("anthropic/claude-sonnet-4-5#high"))
    assert.is_false(opencode2.is_valid_model("sonnet-4.6"))
    assert.is_false(opencode2.is_valid_model("no-slash"))
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

    opencode2.send({ prompt = "do the thing", cwd = "/tmp" }, {
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

    assert.same({ "opencode2", "run", "do the thing" }, seen_cmd)
    assert.equals("/tmp", seen_opts.cwd)
    assert.same({ "hello ", "world" }, chunks)

    on_exit_cb({ code = 0 })
    assert.equals("hello world", done_result.text)
  end)

  it("folds the system prompt and passes --session and --model", function()
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    opencode2.send({
      prompt = "do the thing",
      system = "be terse",
      session_id = "abc123",
      model = "anthropic/claude-sonnet-4-5#high",
      cwd = "/tmp",
    }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "opencode2",
      "run",
      "be terse\n\ndo the thing",
      "--session",
      "abc123",
      "--model",
      "anthropic/claude-sonnet-4-5#high",
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

    opencode2.send({ prompt = "x", cwd = "/tmp" }, {
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

    local handle = opencode2.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    handle.cancel()
    assert.equals(15, killed_with)
  end)
end)