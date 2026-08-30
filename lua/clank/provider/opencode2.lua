local registry = require("clank.provider")
local opencode = require("clank.provider.opencode")

-- OpenCode 2 runs as a separate `opencode2` binary (npm @opencode-ai/cli@beta)
-- that keeps the V1 `run` contract. Both versions can be installed side by
-- side, so opencode and opencode2 are distinct providers here.
local opencode2 = opencode.make("opencode2", "opencode2")
registry.register("opencode2", opencode2)

return opencode2
