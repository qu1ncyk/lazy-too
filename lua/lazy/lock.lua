local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")
local Process = require("lazy.manage.process")

local M = {}

---@class FetchData
---@field fetcher string
---@field args table<string, string>

---Run a command and return only the `stdout` (discard `stderr`).
---@param command string[] | string
---@return string
local function exec_stdout(command)
  local total_data = ""

  ---@param data string
  ---@param is_stderr? boolean
  local function on_data(data, is_stderr)
    if not is_stderr then
      total_data = total_data .. data
    end
  end

  Process.exec(command, { on_data = on_data, args = {} })
  return total_data
end

---Translate a call to `fetchgit` to a more specialized fetcher like
---`fetchFromGitHub` or `fetchFromSourcehut`. Such specialized fetchers are
---more performant as they only download an archive of the selected commit
---instead of a larger part of the repo.
---@param fetch_data FetchData
local function translate_fetchgit(fetch_data)
  if fetch_data.fetcher ~= "fetchgit" then
    return fetch_data
  end

  local command = { "nurl", "-p", fetch_data.args.url, fetch_data.args.rev }
  local json = exec_stdout(command)
  if json == "" then
    return fetch_data
  end
  local parsed = vim.json.decode(json) --[[@as FetchData]]
  parsed.args.hash = fetch_data.args.hash
  return parsed
end

---Fetch the metadata and hash of the repo that hosts the plugin. This function
---is used if `prefetch` using `nurl` fails, for example due to
---`Error: fetchgit does not support fetching the latest revision`.
---@param plugin LazyPlugin
---@return FetchData
local function prefetch_git(plugin)
  local command = { "nix-prefetch-git", plugin.url }
  if plugin.branch then
    vim.list_extend(command, { "--branch-name", plugin.branch })
  end

  if plugin.submodules then
    table.insert(command, "--fetch-submodules")
  end

  ---@todo support semantic versioning
  if plugin.commit then
    table.insert(command, plugin.commit)
  elseif plugin.tag then
    table.insert(command, plugin.tag)
  end

  local json = exec_stdout(command)
  local parsed = vim.json.decode(json) --[[@as table<string, string>]]

  return translate_fetchgit({
    fetcher = "fetchgit",
    args = {
      url = parsed.url,
      hash = parsed.hash,
      rev = parsed.rev,
    },
  })
end

---Fetch the metadata and hash of the repo that hosts the plugin.
---@param plugin LazyPlugin
---@return FetchData
local function prefetch(plugin)
  local command = { "nurl", "-j", plugin.url }
  if plugin.branch then
    -- Not all fetchers support fetching the latest commit from a specific
    -- branch
    return prefetch_git(plugin)
  end

  if plugin.submodules then
    table.insert(command, "--submodules=true")
  else
    table.insert(command, "--submodules=false")
  end

  if plugin.commit then
    table.insert(command, plugin.commit)
  elseif plugin.tag or plugin.version then
    -- Tags don't get translated to commit hashes by nurl,
    -- which makes them not reproducable
    return prefetch_git(plugin)
  end

  local lines = Process.exec(command)
  local json = table.concat(lines)
  local success, parsed = pcall(vim.json.decode, json)

  if not success then
    return prefetch_git(plugin)
  end
  return parsed
end

---Write a JSON object that will be used in the lockfile
---@param opts LazyConfig
function M.write_lockfile(opts)
  local file = io.open(vim.env.out, "w")
  if file == nil then
    error("Failed to open $out (" .. vim.env.out .. ")")
  end

  if type(opts.spec) == "string" then
    opts.spec = { import = opts.spec }
  end

  Config.setup(opts)
  local plugins = Plugin.Spec.new(opts.spec, opts)

  local prefetched_plugins = {}
  for name, plugin in pairs(plugins.meta.plugins) do
    if plugin.url then
      print("Prefetching", name, "from", plugin.url)
      prefetched_plugins[name] = prefetch(plugin)
    else
      print("Skipping", name)
    end
  end

  file:write(vim.json.encode(prefetched_plugins))
  file:close()
end

return M
