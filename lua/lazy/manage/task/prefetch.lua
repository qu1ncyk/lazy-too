local Config = require("lazy.core.config")
local Process = require("lazy.manage.process")
local Semver = require("lazy.manage.semver")

---@type table<string, LazyTaskDef>
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

M.prefetch = {
  skip = function(plugin)
    -- Ignore local plugins
    return not plugin.url
  end,

  ---Prefetch a single plugin and write the result to the `out` table.
  ---@async
  ---@param opts { out: table<string, table> }
  run = function(self, opts)
    local plugin = self.plugin
    opts.out[plugin.name] = prefetch(plugin)
  end,
}

---Fetch all version numbers of a given git repo.
---@param repo_url string
---@return TaggedSemver[]
local function fetch_versions(repo_url)
  local out = {}

  -- From `man git-ls-remote`:
  -- > The output is in the format:
  -- >
  -- >     <oid> TAB <ref> LF
  local tag_lines = Process.exec({ "git", "ls-remote", "--tags", repo_url })
  for _, line in ipairs(tag_lines) do
    local version_str = line:gsub(".*refs/tags/", "")

    local version = Semver.version(version_str)
    if version then
      ---@cast version TaggedSemver
      version.tag = version_str
      table.insert(out, version)
    end
  end

  return out
end

M.version = {
  skip = function(plugin)
    if plugin.tag or plugin.commit then
      return true
    end
    local version = (plugin.version == nil and plugin.branch == nil) and Config.options.defaults.version
      or plugin.version
    return not version
  end,

  ---For plugins with `version` set, use the latest matching tag.
  run = function(self)
    local version = (self.plugin.version == nil and self.plugin.branch == nil) and Config.options.defaults.version
      or self.plugin.version

    local versions = fetch_versions(self.plugin.url)
    local range = Semver.range(version)

    ---@param version TaggedSemver
    local matches = vim.tbl_filter(function(version)
      return range:matches(version)
    end, versions)

    local latest_version = Semver.last(matches)
    if latest_version then
      self.plugin.tag = latest_version.tag
    end
  end,
}

return M
