local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")
local Process = require("lazy.manage.process")

local M = {}

---@class FetchData
---@field fetcher string
---@field args table<string, string>
---@field name string

---Fetch the metadata and hash of the repo that hosts the plugin. This function
---is used if `prefetch` using `nurl` fails, for example due to
---`Error: fetchgit does not support fetching the latest revision`.
---@param plugin LazyPlugin
---@return FetchData
local function prefetch_git(plugin)
  local lines = Process.exec({ "nix-prefetch-git", plugin.url })
  local json = table.concat(lines)
  local parsed = vim.json.decode(json) --[[@as table<string, string>]]
  return {
    fetcher = "fetchgit",
    args = {
      url = parsed.url,
      hash = parsed.hash,
      rev = parsed.rev,
    },
    name = plugin.name,
  }
end

---Fetch the metadata and hash of the repo that hosts the plugin.
---@param plugin LazyPlugin
---@return FetchData
local function prefetch(plugin)
  local lines = Process.exec({ "nurl", "-j", plugin.url })
  local json = table.concat(lines)
  if json == "" then
    return prefetch_git(plugin)
  end
  local parsed = vim.json.decode(json) --[[@as FetchData]]
  parsed.name = plugin.name
  return parsed
end

---Write a JSON object that will be used in the lockfile
---@param opts LazyConfig
function M.write_lockfile(opts)
  local file = io.open(vim.env.out, "w")
  if file == nil then
    error("Failed to open $out (" .. vim.env.out .. ")")
  end

  Config.setup(opts)
  local plugins = Plugin.Spec.new(opts.spec, opts)

  local prefetched_plugins = {}
  for i, plugin in ipairs(plugins.fragments) do
    print("Prefetching", plugin.name, "from", plugin.url)
    prefetched_plugins[i] = prefetch(plugin)
  end

  file:write(vim.json.encode(prefetched_plugins))
  file:close()
end

return M
