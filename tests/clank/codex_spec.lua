local registry = require("clank.provider")
require("clank.provider.codex")

describe("codex provider", function()
  local codex = registry.get("codex")
  local orig_system
  local saved_codex

  before_each(function()
    orig_system = vim.system
    local plugin = require("clank")
    saved_codex = vim.deepcopy(plugin.config.codex)
    plugin.config.codex = {
      sandbox = "workspace-write",
      yolo = false,
      skip_git_repo_check = true,
      extra_args = {},
    }
  end)

  after_each(function()
    vim.system = orig_system
    require("clank").config.codex = saved_codex
  end)

  it("is registered under its name", function()
    assert.equals("codex", codex.name)
  end)

  it("accepts bare model names, rejects empties", function()
    assert.is_true(codex.is_valid_model("gpt-5.6"))
    assert.is_true(codex.is_valid_model("codex-mini-latest"))
    assert.is_false(codex.is_valid_model(""))
    assert.is_false(codex.is_valid_model("some model"))
  end)

  it("builds the expected default command and reports success", function()
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

    codex.send({ prompt = "do the thing", cwd = "/tmp" }, {
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

    assert.same({
      "codex",
      "exec",
      "do the thing",
      "--sandbox",
      "workspace-write",
      "--skip-git-repo-check",
    }, seen_cmd)
    assert.equals("/tmp", seen_opts.cwd)
    assert.same({ "hello ", "world" }, chunks)

    on_exit_cb({ code = 0 })
    assert.equals("hello world", done_result.text)
  end)

  it("folds the system prompt and passes --model", function()
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    codex.send({
      prompt = "do the thing",
      system = "be terse",
      model = "gpt-5.6",
      cwd = "/tmp",
    }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "codex",
      "exec",
      "be terse\n\ndo the thing",
      "--sandbox",
      "workspace-write",
      "--skip-git-repo-check",
      "--model",
      "gpt-5.6",
    }, seen_cmd)
  end)

  it("uses yolo flag instead of sandbox when configured", function()
    require("clank").config.codex = {
      sandbox = "workspace-write",
      yolo = true,
      skip_git_repo_check = true,
      extra_args = {},
    }
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    codex.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "codex",
      "exec",
      "x",
      "--dangerously-bypass-approvals-and-sandbox",
      "--skip-git-repo-check",
    }, seen_cmd)
  end)

  it("honours sandbox, skip_git_repo_check, and extra_args overrides", function()
    require("clank").config.codex = {
      sandbox = "read-only",
      yolo = false,
      skip_git_repo_check = false,
      extra_args = { "--search" },
    }
    local seen_cmd

    vim.system = function(cmd, opts, on_exit)
      seen_cmd = cmd
      return {
        kill = function() end,
      }
    end

    codex.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    assert.same({
      "codex",
      "exec",
      "x",
      "--sandbox",
      "read-only",
      "--search",
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

    codex.send({ prompt = "x", cwd = "/tmp" }, {
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

    local handle = codex.send({ prompt = "x", cwd = "/tmp" }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function() end,
    })

    handle.cancel()
    assert.equals(15, killed_with)
  end)
end)
