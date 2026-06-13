local plugin = require("clank")

describe("setup", function()
  it("works with default", function()
    plugin.setup()
    assert(plugin.config.harness == "claude", "default harness is claude")
    assert(plugin.config.model == "sonnet-4.6", "default model is sonnet-4.6")
  end)

  it("works with custom var", function()
    plugin.setup({ harness = "claude", model = "sonnet-4.6" })
    assert(plugin.config.harness == "claude", "custom harness is claude")
    assert(plugin.config.model == "sonnet-4.6", "custom model is sonnet-4.6")
  end)
end)


describe("is_valid_harness", function()
  it("returns true for valid harness", function()
    assert(plugin.is_valid_harness("claude") == true, "claude is a valid harness")
  end)

  it("returns false for invalid harness", function()
    assert(plugin.is_valid_harness("invalid") == false, "invalid is not a valid harness")
  end)
end)

describe("is_valid_model", function()
  it("returns true for valid model", function()
    assert(plugin.is_valid_model("sonnet-4.6") == true, "sonnet-4.6 is a valid model")
  end)

  it("returns false for invalid model", function()
    assert(plugin.is_valid_model("invalid") == false, "invalid is not a valid model")
  end)
end)
