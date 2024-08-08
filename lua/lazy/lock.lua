local Config = require("lazy.core.config")
local Manage
local Plugin

local M = {}

---Write a JSON object that will be used in the lockfile
---@param opts LazyConfig
function M.write_lockfile(opts)
  local file = io.open(vim.env.out, "w")
  if file == nil then
    error("Failed to open $out (" .. vim.env.out .. ")")
  end

  Config.setup(opts)
  Manage = require("lazy.manage")
  Plugin = require("lazy.core.plugin")
  Plugin.load()

  local prefetched_plugins = Manage.prefetch()
  file:write(vim.json.encode(prefetched_plugins))
  file:close()
end

return M
