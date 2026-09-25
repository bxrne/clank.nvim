local custom = require("clank.custom")

describe("custom command runner", function()
  local orig_system

  before_each(function()
    orig_system = vim.system
  end)

  after_each(function()
    vim.system = orig_system
  end)

  it("validates string and argv specs", function()
    assert.is_true(custom.is_valid_spec("mycli --fill"))
    assert.is_true(custom.is_valid_spec({ "mycli", "--fill" }))
    assert.is_false(custom.is_valid_spec(""))
    assert.is_false(custom.is_valid_spec("   "))
    assert.is_false(custom.is_valid_spec({}))
    assert.is_false(custom.is_valid_spec({ "mycli", 42 }))
    assert.is_false(custom.is_valid_spec(nil))
  end)

  it("pipes the prompt via stdin and captures stdout", function()
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

    custom.send("mycli --fill", { prompt = "do the thing", cwd = "/tmp" }, {
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

    assert.equals("mycli --fill", seen_cmd)
    assert.equals("do the thing", seen_opts.stdin)
    assert.equals("/tmp", seen_opts.cwd)
    assert.same({ "hello ", "world" }, chunks)

    on_exit_cb({ code = 0 })
    assert.equals("hello world", done_result.text)
  end)

  it("accepts argv lists and folds the system prompt into stdin", function()
    local seen_cmd, seen_opts

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      seen_opts = opts
      return {
        kill = function() end,
      }
    end

    custom.send({ "mycli", "run" }, {
      prompt = "do the thing",
      system = "be terse",
      cwd = "/tmp",
    }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({ "mycli", "run" }, seen_cmd)
    assert.equals("be terse\n\ndo the thing", seen_opts.stdin)
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

    custom.send("mycli", { prompt = "x", cwd = "/tmp" }, {
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

    local handle = custom.send("mycli", { prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    handle.cancel()
    assert.equals(15, killed_with)
  end)
end)
