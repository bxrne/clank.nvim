local pr = require("clank.pr")
local plugin = require("clank")

describe("worktree_path", function()
  it("builds a sibling directory named <repo>-pr-<n>", function()
    assert.equals("/home/user/foo-pr-42", pr.worktree_path("/home/user/foo", 42))
  end)
end)

describe("branch_name", function()
  it("namespaces the local branch under clank-pr-<n>", function()
    assert.equals("clank-pr-42", pr.branch_name(42))
  end)
end)

describe("fetch_pr_ref", function()
  it("fetches the PR head into a local branch", function()
    local seen_cmd
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      seen_cmd = cmd
      return {
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end

    local ok, err = pr.fetch_pr_ref(42, "/tmp")
    vim.system = orig_system

    assert.same({ "git", "fetch", "origin", "pull/42/head:clank-pr-42" }, seen_cmd)
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("returns an error when the fetch fails", function()
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "fatal: couldn't find remote ref" }
        end,
      }
    end

    local ok, err = pr.fetch_pr_ref(42, "/tmp")
    vim.system = orig_system

    assert.is_false(ok)
    assert.equals("fatal: couldn't find remote ref", err)
  end)
end)

describe("add_worktree", function()
  it("adds a worktree at the given path on the given branch", function()
    local seen_cmd
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      seen_cmd = cmd
      return {
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end

    local ok = pr.add_worktree("/tmp/repo", "/tmp/repo-pr-42", "clank-pr-42")
    vim.system = orig_system

    assert.same({ "git", "worktree", "add", "/tmp/repo-pr-42", "clank-pr-42" }, seen_cmd)
    assert.is_true(ok)
  end)
end)

describe("open", function()
  local orig_system
  local orig_notify
  local orig_isdirectory
  local orig_tcd

  before_each(function()
    plugin.setup()
    orig_system = vim.system
    orig_notify = vim.notify
    orig_isdirectory = vim.fn.isdirectory
    orig_tcd = vim.cmd.tcd
    vim.cmd.tcd = function() end
  end)

  after_each(function()
    vim.system = orig_system
    vim.notify = orig_notify
    vim.fn.isdirectory = orig_isdirectory
    vim.cmd.tcd = orig_tcd
  end)

  it("notifies and skips when gh is not available", function()
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(name)
      if name == "gh" then
        return 0
      end
      return orig_executable(name)
    end

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    pr.open(42)

    vim.fn.executable = orig_executable
    assert.truthy(notified:find("gh is not available", 1, true))
  end)

  it("fetches and adds a worktree, then tcds into it, when it doesn't exist yet", function()
    vim.fn.isdirectory = function()
      return 0
    end

    local cmds = {}
    vim.system = function(cmd, opts)
      table.insert(cmds, cmd)
      return {
        wait = function()
          if cmd[2] == "rev-parse" then
            return { code = 0, stdout = "true\n", stderr = "" }
          end
          if cmd[1] == "gh" then
            return { code = 0, stdout = "[]", stderr = "" }
          end
          return { code = 0, stdout = "", stderr = "" }
        end,
      }
    end

    local tcd_path
    vim.cmd.tcd = function(path)
      tcd_path = path
    end

    local notified
    vim.notify = function(msg, _)
      notified = msg
    end

    pr.open(42)

    assert.truthy(cmds[2][1] == "git" and cmds[2][2] == "fetch")
    assert.truthy(cmds[3][1] == "git" and cmds[3][2] == "worktree")
    assert.truthy(tcd_path:find("-pr-42", 1, true))
    assert.truthy(notified:find("opened PR #42", 1, true))
  end)

  it("skips fetch/add and just tcds when the worktree already exists", function()
    vim.fn.isdirectory = function()
      return 1
    end

    local cmds = {}
    vim.system = function(cmd, opts)
      table.insert(cmds, cmd)
      return {
        wait = function()
          if cmd[1] == "gh" then
            return { code = 0, stdout = "[]", stderr = "" }
          end
          return { code = 0, stdout = "true\n", stderr = "" }
        end,
      }
    end

    local tcd_path
    vim.cmd.tcd = function(path)
      tcd_path = path
    end

    pr.open(42)

    assert.equals(2, #cmds)
    assert.truthy(tcd_path:find("-pr-42", 1, true))
  end)

  it("loads existing PR review comments into the quickfix list", function()
    vim.fn.isdirectory = function()
      return 1
    end

    vim.system = function(cmd, opts)
      return {
        wait = function()
          if cmd[1] == "gh" then
            return {
              code = 0,
              stdout = vim.json.encode({
                { path = "foo.lua", line = 12, user = { login = "octocat" }, body = "consider a guard clause" },
              }),
              stderr = "",
            }
          end
          return { code = 0, stdout = "true\n", stderr = "" }
        end,
      }
    end

    pr.open(42)

    local qf = vim.fn.getqflist()
    assert.equals(1, #qf)
    assert.equals(12, qf[1].lnum)
    assert.truthy(qf[1].text:find("octocat", 1, true))
  end)
end)

describe("pr_number_from_cwd", function()
  it("extracts the PR number from a ClankPR worktree path", function()
    assert.equals(42, pr.pr_number_from_cwd("/home/user/foo-pr-42"))
  end)

  it("returns nil for a path that isn't a ClankPR worktree", function()
    assert.is_nil(pr.pr_number_from_cwd("/home/user/foo"))
  end)
end)

describe("get_comments", function()
  it("maps GitHub review comments to quickfix items", function()
    local seen_cmd
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      seen_cmd = cmd
      return {
        wait = function()
          return {
            code = 0,
            stdout = vim.json.encode({
              { path = "foo.lua", line = 12, user = { login = "octocat" }, body = "consider a guard clause" },
              { path = "bar.lua", original_line = 3, user = { login = "hubot" }, body = "line1\nline2" },
            }),
            stderr = "",
          }
        end,
      }
    end

    local items, err = pr.get_comments(42, "/tmp")
    vim.system = orig_system

    assert.same({ "gh", "api", "repos/{owner}/{repo}/pulls/42/comments" }, seen_cmd)
    assert.is_nil(err)
    assert.same({
      { filename = "foo.lua", lnum = 12, text = "octocat: consider a guard clause" },
      { filename = "bar.lua", lnum = 3, text = "hubot: line1 line2" },
    }, items)
  end)

  it("returns an error when gh fails", function()
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "no pull requests found" }
        end,
      }
    end

    local items, err = pr.get_comments(42, "/tmp")
    vim.system = orig_system

    assert.is_nil(items)
    assert.equals("no pull requests found", err)
  end)
end)

describe("add_comment", function()
  after_each(function()
    pr.drafts = {}
  end)

  it("queues a draft comment under the PR number", function()
    pr.add_comment(42, "foo.lua", 12, "needs a nil check")
    assert.same({ { path = "foo.lua", line = 12, body = "needs a nil check" } }, pr.drafts[42])
  end)
end)

describe("submit_review", function()
  after_each(function()
    pr.drafts = {}
  end)

  it("posts a review with the head sha, event, body and queued comments, then clears the queue", function()
    pr.drafts[42] = { { path = "foo.lua", line = 12, body = "needs a nil check" } }

    local seen_cmd, seen_opts
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      if cmd[1] == "git" then
        return {
          wait = function()
            return { code = 0, stdout = "deadbeef\n", stderr = "" }
          end,
        }
      end
      seen_cmd = cmd
      seen_opts = opts
      return {
        wait = function()
          return { code = 0, stdout = "{}", stderr = "" }
        end,
      }
    end

    local ok, err = pr.submit_review(42, "/tmp", "COMMENT", "looks good overall")
    vim.system = orig_system

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({ "gh", "api", "-X", "POST", "repos/{owner}/{repo}/pulls/42/reviews", "--input", "-" }, seen_cmd)

    local payload = vim.json.decode(seen_opts.stdin)
    assert.equals("deadbeef", payload.commit_id)
    assert.equals("COMMENT", payload.event)
    assert.equals("looks good overall", payload.body)
    assert.same({ { path = "foo.lua", line = 12, body = "needs a nil check" } }, payload.comments)
    assert.is_nil(pr.drafts[42])
  end)

  it("returns an error when the API call fails", function()
    local orig_system = vim.system
    vim.system = function(cmd, opts)
      if cmd[1] == "git" then
        return {
          wait = function()
            return { code = 0, stdout = "deadbeef\n", stderr = "" }
          end,
        }
      end
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "Validation Failed" }
        end,
      }
    end

    local ok, err = pr.submit_review(42, "/tmp", "APPROVE", "")
    vim.system = orig_system

    assert.is_false(ok)
    assert.equals("Validation Failed", err)
  end)
end)
