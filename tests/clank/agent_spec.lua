local agent = require("clank.agent")
local registry = require("clank.provider")
local plugin = require("clank")

describe("build_prompt", function()
  it("embeds the task and describes the JSON action schema", function()
    local prompt = agent.build_prompt("review all hotspots")
    assert.truthy(prompt:find("review all hotspots", 1, true))
    assert.truthy(prompt:find('"actions"', 1, true))
    assert.truthy(prompt:find('"type": "command"', 1, true))
    assert.truthy(prompt:find('"type": "qflist"', 1, true))
    assert.truthy(prompt:find('"type": "edit"', 1, true))
  end)
end)

describe("extract_json", function()
  it("returns bare JSON unchanged", function()
    assert.equals('{"actions":[]}', agent.extract_json('{"actions":[]}'))
  end)

  it("unwraps a ```json fenced block", function()
    local text = "sure!\n```json\n{\"actions\": []}\n```\n"
    assert.equals('{"actions": []}', agent.extract_json(text))
  end)

  it("unwraps a plain fenced block", function()
    local text = "```\n{\"actions\": []}\n```"
    assert.equals('{"actions": []}', agent.extract_json(text))
  end)

  it("slices from the first brace to the last brace when there is surrounding prose", function()
    local text = "Here is the plan: {\"actions\": [{\"type\": \"command\"}]} hope that helps"
    assert.equals('{"actions": [{"type": "command"}]}', agent.extract_json(text))
  end)
end)

describe("parse_actions", function()
  it("parses a valid actions array", function()
    local actions, err = agent.parse_actions('{"actions":[{"type":"command","command":"copen"}]}')
    assert.is_nil(err)
    assert.equals(1, #actions)
    assert.equals("command", actions[1].type)
    assert.equals("copen", actions[1].command)
  end)

  it("returns an empty list for no actions", function()
    local actions, err = agent.parse_actions('{"actions":[]}')
    assert.is_nil(err)
    assert.same({}, actions)
  end)

  it("errors on invalid JSON", function()
    local actions, err = agent.parse_actions("not json at all")
    assert.is_nil(actions)
    assert.truthy(err:find("could not parse JSON", 1, true))
  end)

  it("errors when there is no actions array", function()
    local actions, err = agent.parse_actions('{"foo": 1}')
    assert.is_nil(actions)
    assert.truthy(err:find("actions", 1, true))
  end)

  it("errors on an empty response", function()
    local actions, err = agent.parse_actions("")
    assert.is_nil(actions)
    assert.truthy(err:find("empty response", 1, true))
  end)
end)

describe("summarize", function()
  it("renders one line per action", function()
    local summary = agent.summarize({
      { type = "command", command = "vsplit" },
      { type = "qflist", action = "a", items = { {}, {} } },
      { type = "edit", path = "lua/foo.lua" },
      { type = "bogus" },
    })
    assert.truthy(summary:find("1. :vsplit", 1, true))
    assert.truthy(summary:find("2. quickfix append (2 item(s))", 1, true))
    assert.truthy(summary:find("3. edit lua/foo.lua", 1, true))
    assert.truthy(summary:find("4. unknown action (bogus)", 1, true))
  end)
end)

describe("execute_action", function()
  it("runs an ex command", function()
    local seen
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      seen = c
    end

    agent.execute_action({ type = "command", command = "echo 'hi'" })

    vim.cmd = orig_cmd
    assert.equals("echo 'hi'", seen)
  end)

  it("replaces the quickfix list", function()
    vim.fn.setqflist({}, "r")
    agent.execute_action({
      type = "qflist",
      action = "r",
      items = { { filename = "foo.lua", lnum = 3, text = "hotspot" } },
    })

    local qf = vim.fn.getqflist()
    assert.equals(1, #qf)
    assert.equals(3, qf[1].lnum)
    assert.equals("hotspot", qf[1].text)
    vim.fn.setqflist({}, "r")
  end)

  it("appends to the quickfix list", function()
    vim.fn.setqflist({ { filename = "a.lua", lnum = 1, text = "one" } }, "r")
    agent.execute_action({
      type = "qflist",
      action = "a",
      items = { { filename = "b.lua", lnum = 2, text = "two" } },
    })

    assert.equals(2, #vim.fn.getqflist())
    vim.fn.setqflist({}, "r")
  end)

  it("replaces a buffer's contents for an edit action", function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ "old line" }, path)

    agent.execute_action({ type = "edit", path = path, content = "new one\nnew two" })

    local bufnr = vim.fn.bufadd(path)
    assert.same({ "new one", "new two" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    os.remove(path)
  end)

  it("errors on an unknown action type", function()
    assert.has_error(function()
      agent.execute_action({ type = "nope" })
    end)
  end)
end)

describe("apply", function()
  local orig_notify
  local orig_confirm

  before_each(function()
    orig_notify = vim.notify
    orig_confirm = vim.fn.confirm
    vim.notify = function() end
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.fn.confirm = orig_confirm
    vim.fn.setqflist({}, "r")
  end)

  it("skips confirmation when confirm = false", function()
    local confirmed = false
    vim.fn.confirm = function()
      confirmed = true
      return 1
    end

    agent.apply({ { type = "qflist", action = "r", items = { { text = "x" } } } }, { confirm = false })

    assert.is_false(confirmed)
    assert.equals(1, #vim.fn.getqflist())
  end)

  it("aborts without executing when the user declines confirmation", function()
    vim.fn.confirm = function()
      return 2
    end

    agent.apply({ { type = "qflist", action = "r", items = { { text = "x" } } } }, { confirm = true })

    assert.equals(0, #vim.fn.getqflist())
  end)

  it("continues past a failing action and applies the rest", function()
    vim.fn.confirm = function()
      return 1
    end

    agent.apply({
      { type = "bogus" },
      { type = "qflist", action = "r", items = { { text = "ok" } } },
    }, { confirm = true })

    assert.equals(1, #vim.fn.getqflist())
  end)
end)

describe("run", function()
  local original_harness
  local orig_notify

  before_each(function()
    plugin.setup()
    original_harness = plugin.config.harness
    orig_notify = vim.notify
    vim.notify = function() end
  end)

  after_each(function()
    plugin.config.harness = original_harness
    vim.notify = orig_notify
    vim.fn.setqflist({}, "r")
  end)

  it("notifies and skips when the prompt is empty", function()
    local notified
    vim.notify = function(msg)
      notified = msg
    end

    agent.run("   ")

    assert.truthy(notified:find("requires a prompt", 1, true))
  end)

  it("executes the actions returned by the provider", function()
    registry.register("fake", {
      name = "fake",
      send = function(_, callbacks)
        callbacks.on_done({
          text = '{"actions":[{"type":"qflist","action":"r","items":[{"filename":"foo.lua","lnum":9,"text":"fix me"}]}]}',
        })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake"
    plugin.config.agent = { confirm = false }

    agent.run("add hotspots to my quickfix list")

    vim.wait(100, function()
      return #vim.fn.getqflist() == 1
    end)

    local qf = vim.fn.getqflist()
    assert.equals(1, #qf)
    assert.equals(9, qf[1].lnum)
    assert.equals("fix me", qf[1].text)
  end)

  it("notifies on a parse error from the provider", function()
    registry.register("fake_bad", {
      name = "fake_bad",
      send = function(_, callbacks)
        callbacks.on_done({ text = "sorry, I can't do that" })
        return { cancel = function() end }
      end,
    })
    plugin.config.harness = "fake_bad"
    plugin.config.agent = { confirm = false }

    local notified
    vim.notify = function(msg)
      notified = msg
    end

    agent.run("do something")

    vim.wait(100, function()
      return notified ~= nil and notified:find("parse JSON", 1, true) ~= nil
    end)

    assert.truthy(notified:find("could not parse JSON", 1, true))
  end)
end)
