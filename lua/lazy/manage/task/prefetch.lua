local Config = require("lazy.core.config")
local Process = require("lazy.manage.process")
local Rockspec = require("lazy.pkg.rockspec")
local Semver = require("lazy.manage.semver")
local Util = require("lazy.util")

---@type table<string, LazyTaskDef>
local M = {}

---@class FetchData
---@field fetcher string
---@field args table<string, string>

---@class RockData
---@field hash string The hash of either `src_rock` or `rockspec`
---@field src_rock string? URL to `.src.rock` file
---@field rockspec string? URL to `.rockspec` file
---@field src FetchData? Source used in `.rockspec`

---@class GitRepoData
---@field url string?
---@field branch? string
---@field tag? string
---@field commit? string
---@field version? string|boolean
---@field pin? boolean
---@field submodules? boolean Defaults to true

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
  local json = Process.exec_stdout(command)
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
---@param repo GitRepoData | LazyPlugin
---@return FetchData
local function prefetch_git(repo)
  local command = { "nix-prefetch-git", repo.url }
  if repo.branch then
    vim.list_extend(command, { "--branch-name", repo.branch })
  end

  if repo.submodules then
    table.insert(command, "--fetch-submodules")
  end

  if repo.commit then
    table.insert(command, repo.commit)
  elseif repo.tag then
    table.insert(command, repo.tag)
  end

  local json = Process.exec_stdout(command)
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
---@param repo GitRepoData | LazyPlugin
---@return FetchData
local function prefetch(repo)
  local command = { "nurl", "-j", repo.url }
  if repo.branch then
    -- Not all fetchers support fetching the latest commit from a specific
    -- branch
    return prefetch_git(repo)
  end

  if repo.submodules then
    table.insert(command, "--submodules=true")
  else
    table.insert(command, "--submodules=false")
  end

  if repo.commit then
    table.insert(command, repo.commit)
  elseif repo.tag or repo.version then
    -- Tags don't get translated to commit hashes by nurl,
    -- which makes them not reproducable
    return prefetch_git(repo)
  end

  local lines = Process.exec(command)
  local json = table.concat(lines)
  local success, parsed = pcall(vim.json.decode, json)

  if not success then
    return prefetch_git(repo)
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
  ---@param opts { out: table<string, FetchData> }
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

---Convert a Lua value to a Nix expression.
---@return string
local function convert_to_nix(val)
  local t = type(val)
  if t == "boolean" or t == "number" then
    return tostring(val)
  elseif t == "string" then
    return '"'
      .. string.gsub(val, [[\]], [[\\]]):gsub('"', [[\"]]):gsub("\t", [[\t]]):gsub("\n", [[\n]]):gsub("\r", [[\r]])
      .. '"'
  elseif t == "table" then
    local out = ""
    for k, v in pairs(val) do
      out = out .. convert_to_nix(tostring(k)) .. "=" .. convert_to_nix(v) .. ";"
    end
    return "{" .. out .. "}"
  else
    return "null"
  end
end

M.download = {
  ---@param opts { fetchData: table<string, FetchData>, store_path: table<string, string> }
  skip = function(plugin, opts)
    return not opts.fetchData[plugin.name]
  end,

  ---Download the prefetched plugin and store the `/nix/store` path.
  ---@async
  ---@param opts { fetchData: table<string, FetchData>, store_paths: table<string, string> }
  run = function(self, opts)
    local fetchData = opts.fetchData[self.plugin.name]
    local fetcher = fetchData.fetcher
    local args = fetchData.args
    local lines = Process.exec({
      "nix-build",
      "--no-out-link",
      "--expr",
      "(import <nixpkgs> {})." .. fetcher .. " " .. convert_to_nix(args),
    })
    local store_path = lines[#lines - 1]

    assert(string.sub(store_path, 1, 11) == "/nix/store/")
    opts.store_paths[self.plugin.name] = store_path
  end,
}

M.lazy_lua = {
  ---Get the contents of this plugin's `lazy.lua` and store them.
  ---@param opts { store_paths: table<string, string>, specs: table<string, table> }
  run = function(self, opts)
    local dir = opts.store_paths[self.plugin.name] or self.plugin.dir
    local file = dir .. "/lazy.lua"
    if Util.file_exists(file) then
      local spec = loadfile(file)()
      opts.specs[self.plugin.name] = spec
    end
  end,
}

---Find a rockspec in the given dir.
---Adaped from `pkg/rockspec.lua`.
---@param dir string
---@return string?
local function find_rockspec(dir)
  local rockspec_file ---@type string?
  Util.ls(dir, function(path, name, t)
    if t == "file" then
      for _, suffix in ipairs({ "scm", "git", "dev" }) do
        suffix = suffix .. "-1.rockspec"
        if name:sub(-#suffix) == suffix then
          rockspec_file = path
          return false
        end
      end
    end
  end)
  return rockspec_file
end

M.rockspec = {
  ---@param opts { store_paths: table<string, string>, rockspecs: table<string, string>, lazy_lua_specs: table<string, table> }
  skip = function(plugin, opts)
    return opts.lazy_lua_specs[plugin.name] and true or false
  end,

  ---Get the contents of this plugin's `lazy.lua` and store them.
  ---@param opts { store_paths: table<string, string>, rockspecs: table<string, string>, lazy_lua_specs: table<string, table> }
  run = function(self, opts)
    local dir = opts.store_paths[self.plugin.name] or self.plugin.dir
    local file = find_rockspec(dir)
    if file then
      opts.rockspecs[self.plugin.name] = file
    end
  end,
}

---Convert a list of pairs to a dictionary-like table.
---@param pairs [string, string][]
---@return table<string, string>
local function pairs_to_dict(pairs)
  local out = {}
  for _, pair in ipairs(pairs) do
    out[pair[1]] = pair[2]
  end
  return out
end

M.rockspec_deps = {
  ---@param opts { rockspecs: table<string, string> }
  skip = function(plugin, opts)
    return not opts.rockspecs[plugin.name]
  end,

  ---Get the dependency versions of the rockspec and store them.
  ---@param opts { rockspecs: table<string, string>, rockspec_deps: table<string, table<string, string>> }
  run = function(self, opts)
    -- @todo Rewrite this function to get the dependency versions without
    -- building/installing everything during lock phase. This works but it is slow.
    local tmp = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/lazy-too.XXXXXX")
    local tree = tmp and tmp .. "/tree"
    local src = tmp and tmp .. "/src"
    assert(tmp, "Could not create a temporary directory")

    local ok = Util.try(function()
      -- During the installation of a rock, luarocks can move a file from one place
      -- to another. Since that file originates from the Nix store, it has no
      -- write permission. Moving the file fails. The code below works around that
      -- by copying the entire rock source to a temporary dir and by making it writable.
      local name = self.plugin.name

      local parent = vim.fs.dirname(opts.rockspecs[name])
      local output, status = Process.exec({ "cp", "-r", parent, src })
      assert(status == 0, "Could not copy the source of rock " .. name .. ": " .. table.concat(output, "\n"))
      output, status = Process.exec({ "chmod", "-R", "u+w", src })
      assert(status == 0, "Could not make the source of rock " .. name .. " writable: " .. table.concat(output, "\n"))

      -- `luarocks make` uses the CWD as the source of the rock and
      -- `$HOME/.cache/luarocks/https___luarocks.org/lockfile.lfs` as lockfile
      output, status = Process.exec({
        "luarocks",
        "--tree",
        tree,
        "make",
        "--deps-only",
      }, {
        cwd = src,
        env = { HOME = tmp },
      })
      assert(status == 0, "Could not build rock " .. name .. ":\n" .. table.concat(output, "\n"))

      -- Remove `src` so that it doesn't interfere with the next rock in the loop
      output, status = Process.exec({ "rm", "-r", src })
      assert(status == 0, "Could not remove the copied source of rock " .. name .. ": " .. table.concat(output, "\n"))

      local lines
      lines, status = Process.exec({ "luarocks", "--tree", tree, "list", "--porcelain" })
      assert(status == 0, "Could not get a list of the installed rocks")
      table.remove(lines, #lines)

      opts.rockspec_deps[name] = pairs_to_dict(vim.tbl_map(function(line)
        local split = vim.split(line, "\t")
        return vim.list_slice(split, 1, 2)
      end, lines))
      return true
    end)

    Process.exec({ "rm", "-r", tmp })
    if not ok then
      error(ok)
    end
  end,
}

---@param base32 string
local function base32_to_sri(base32)
  local stdout, status = Process.exec_stdout({
    "nix-hash",
    "--type",
    "sha256",
    "--to-sri",
    base32,
  })
  assert(status == 0, "Could not convert the hash to SRI")
  return stdout:gsub("%s", "")
end

---Prefetch a `.src.rock` from LuaRocks.
---@param name string
---@param version string
---@return RockData
local function prefetch_src_rock(name, version)
  local url = "https://luarocks.org/" .. name .. "-" .. version .. ".src.rock"
  local stdout, status = Process.exec_stdout({ "nix-prefetch-url", url })
  local base32 = stdout:gsub("%s", "")
  assert(status == 0, "Could not prefetch " .. url)

  return {
    hash = base32_to_sri(base32),
    src_rock = url,
  }
end

---Rewrite a URL from the [LuaRocks protocol syntax](https://github.com/luarocks/luarocks/wiki/Rockspec-format#build-rules)
---to a format that git understands.
---@param url string
local function rewrite_git_url(url)
  -- Workaround by LuaRocks to keep GitHub `git://` urls working after GitHub
  -- dropped support: https://github.com/luarocks/luarocks/blob/1ada2ea4bbd94ac0c58e3e2cc918194140090a75/src/luarocks/fetch.tl#L582C4-L586C7
  if url:match("^git://github%.com/") or url:match("^git://www%.github%.com/") then
    return url:gsub("^git://", "https://")
  elseif url:match("^git%+%a+://") then
    return url:sub(5)
  elseif url:match("^git://") then
    return url
  else
    error("Unsupported source URL: " .. url)
  end
end

---Prefetch a `.rockspec` from LuaRocks.
---@param name string
---@param version string
---@return RockData
local function prefetch_rockspec(name, version)
  local url = "https://luarocks.org/" .. name .. "-" .. version .. ".rockspec"
  local stdout, status = Process.exec_stdout({ "nix-prefetch-url", url })

  local base32 = stdout:gsub("%s", "")
  assert(status == 0, "Could not prefetch " .. url)
  local hash = base32_to_sri(base32)

  local lines = Process.exec({
    "nix-build",
    "--no-out-link",
    "--expr",
    "(import <nixpkgs> {}).fetchurl " .. convert_to_nix({ url = url, hash = hash }),
  })
  local store_path = lines[#lines - 1]
  assert(string.sub(store_path, 1, 11) == "/nix/store/")

  local rockspec = Rockspec.rockspec(store_path)
  assert(rockspec and rockspec.source.url)

  return {
    hash = hash,
    rockspec = url,
    src = prefetch({
      url = rewrite_git_url(rockspec.source.url),
      tag = rockspec.source.tag,
      branch = rockspec.source.branch,
    }),
  }
end

M.rockspec_download_deps = {
  ---@param opts { rockspec_deps: table<string, table<string, string>> }
  skip = function(plugin, opts)
    return not opts.rockspec_deps[plugin.name]
  end,

  ---Download the source rocks of the dependencies and store their hash.
  ---@param opts { rockspec_deps: table<string, table<string, string>>, rock_data: table<string, table<string, RockData>> }
  run = function(self, opts)
    local data = {}
    for name, version in pairs(opts.rockspec_deps[self.plugin.name]) do
      if not vim.list_contains({ "git", "scm", "dev" }, version:sub(1, 3)) then
        data[name] = prefetch_src_rock(name, version)
      else
        data[name] = prefetch_rockspec(name, version)
      end
    end
    if not vim.tbl_isempty(data) then
      opts.rock_data[self.plugin.name] = data
    end
  end,
}

return M
