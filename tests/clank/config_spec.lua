local plugin = require("clank")

describe("setup commands/codex config", function()
  after_each(function()
    plugin.setup({
      harness = "claude",
      model = "sonnet-4.6",
      commands = {},
      codex = { sandbox = "workspace-write", yolo = false, skip_git_repo_check = true, extra_args = {} },
    })
    -- tbl_deep_extend never removes keys, so drop any stray test keys.
    plugin.config.commands = {}
  end)

  it("defaults commands to empty and codex to workspace-write", function()
    plugin.setup()
    assert.same({}, plugin.config.commands)
    assert.equals("workspace-write", plugin.config.codex.sandbox)
    assert.is_false(plugin.config.codex.yolo)
    assert.is_true(plugin.config.codex.skip_git_repo_check)
    assert.same({}, plugin.config.codex.extra_args)
  end)

  it("accepts harness=custom without model validation", function()
    plugin.setup({ harness = "custom" })
    assert.equals("custom", plugin.config.harness)
  end)

  it("accepts per-action custom commands", function()
    plugin.setup({
      harness = "custom",
      commands = {
        fill = "mycli --fill",
        review = { "mycli", "review" },
        fix = "mycli --fix",
        ["do"] = "mycli --do",
      },
    })
    assert.equals("mycli --fill", plugin.config.commands.fill)
  end)

  it("rejects unknown command actions", function()
    assert.has_error(function()
      plugin.setup({ commands = { nope = "x" } })
    end)
  end)

  it("rejects empty command specs", function()
    assert.has_error(function()
      plugin.setup({ commands = { fill = "" } })
    end)
  end)

  it("rejects invalid codex sandbox values", function()
    assert.has_error(function()
      plugin.setup({ codex = { sandbox = "yolo" } })
    end)
  end)

  it("accepts codex sandbox/yolo/extra_args overrides", function()
    plugin.setup({
      harness = "codex",
      model = "gpt-5.6",
      codex = { sandbox = "read-only", yolo = false, extra_args = { "--search" } },
    })
    assert.equals("read-only", plugin.config.codex.sandbox)
    assert.same({ "--search" }, plugin.config.codex.extra_args)
  end)
end)
