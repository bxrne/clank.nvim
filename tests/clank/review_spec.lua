local review = require("clank.review")
local registry = require("clank.provider")
local plugin = require("clank")

describe("build_prompt", function()
  it("includes the diff and asks for path:line: message lines", function()
    local prompt = review.build_prompt("diff --git a/foo.lua b/foo.lua")
    assert.truthy(prompt:find("diff --git a/foo.lua b/foo.lua", 1, true))
    assert.truthy(prompt:find("path:line: message", 1, true))
  end)
end)

describe("parse_comments", function()
  it("parses path:line: message lines into quickfix items", function()
    local items = review.parse_comments(table.concat({
      "lua/clank/fill.lua:12: missing nil check",
      "lua/clank/review.lua:3: unused variable",
    }, "\n"))

    assert.same({
      { filename = "lua/clank/fill.lua", lnum = 12, text = "missing nil check" },
      { filename = "lua/clank/review.lua", lnum = 3, text = "unused variable" },
    }, items)
  end)

  it("ignores lines that don't match the format", function()
    local items = review.parse_comments("just some prose\nlua/clank/fill.lua:12: real issue")
    assert.same({ { filename = "lua/clank/fill.lua", lnum = 12, text = "real issue" } }, items)
  end)

  it("returns an empty list for empty input", function()
    assert.same({}, review.parse_comments(""))
  end)
end)

describe("get_diff", function()
  it("uses 'git diff HEAD' for n = 0", function()
    local seen_cmd
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      seen_cmd = cmd
      return {
        wait = function()
          return { code = 0, stdout = "diff", stderr = "" }
        end,
      }
    end

    local diff, err = review.get_diff(0, "/tmp")
    vim.system = orig_system

    assert.same({ "git", "diff", "HEAD" }, seen_cmd)
    assert.equals("diff", diff)
    assert.is_nil(err)
  end)

  it("uses 'git diff HEAD~n HEAD~(n-1)' for n > 0", function()
    local seen_cmd
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      seen_cmd = cmd
      return {
        wait = function()
          return { code = 0, stdout = "diff", stderr = "" }
        end,
      }
    end

    review.get_diff(2, "/tmp")
    vim.system = orig_system

    assert.same({ "git", "diff", "HEAD~2", "HEAD~1" }, seen_cmd)
  end)

  it("returns an error when git fails", function()
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "fatal: bad revision" }
        end,
      }
    end

    local diff, err = review.get_diff(1, "/tmp")
    vim.system = orig_system

    assert.is_nil(diff)
    assert.equals("fatal: bad revision", err)
  end)
end)

describe("review", function()
  local original_harness
  local orig_system
  local orig_notify

  before_each(function()
    plugin.setup()
    original_harness = plugin.config.harness
    orig_system = vim.system
    orig_notify = vim.notify
  end)

  after_each(function()
    plugin.config.harness = original_harness
    vim.system = orig_system
    vim.notify = orig_notify
  end)

  it("notifies and skips when git is not available", function()
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(name)
      if name == "git" then
        return 0
      end
      return orig_executable(name)
    end

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    review.review(0)

    vim.fn.executable = orig_executable
    assert.truthy(notified:find("git is not available", 1, true))
  end)

  it("notifies and skips when not inside a git repo", function()
    vim.system = function(cmd, opts)
      return {
        wait = function()
          return { code = 128, stdout = "", stderr = "fatal: not a git repository" }
        end,
      }
    end

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    review.review(0)

    assert.truthy(notified:find("not a git repository", 1, true))
  end)

  it("populates the quickfix list from the provider's response", function()
    vim.system = function(cmd, opts)
      return {
        wait = function()
          if cmd[2] == "rev-parse" then
            return { code = 0, stdout = "true\n", stderr = "" }
          end
          return { code = 0, stdout = "diff --git a/foo.lua b/foo.lua\n", stderr = "" }
        end,
      }
    end

    registry.register("fake", {
      name = "fake",
      send = function(opts, callbacks)
        callbacks.on_done({ text = "foo.lua:1: do not do this" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"

    review.review(0)

    vim.wait(100, function()
      return #vim.fn.getqflist() == 1
    end)

    local qf = vim.fn.getqflist()
    assert.equals(1, #qf)
    assert.equals(1, qf[1].lnum)
    assert.equals("do not do this", qf[1].text)
  end)

  it("notifies without touching the quickfix list when there's nothing to review", function()
    vim.system = function(cmd, opts)
      return {
        wait = function()
          if cmd[2] == "rev-parse" then
            return { code = 0, stdout = "true\n", stderr = "" }
          end
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    review.review(0)

    assert.truthy(notified:find("nothing to review", 1, true))
  end)
end)
