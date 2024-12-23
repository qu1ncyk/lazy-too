local Config = require("lazy.core.config")
local Manage = require("lazy.manage")
local Process = require("lazy.manage.process")
local Util = require("lazy.core.util")

local M = {}

---@class RockData
---@field hash string The hash of `src_rock`
---@field src_rock string URL to `.src.rock` file

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

---Get all dependency versions of the given rock paths.
---@param rockspec_paths table<string, string>
local function luarocks_dependencies(rockspec_paths)
  -- @todo Rewrite this function to get the dependency versions without
  -- building/installing everything during lock phase. This works but it is slow.
  local tmp = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/lazy-too.XXXXXX")
  local tree = tmp and tmp .. "/tree"
  local src = tmp and tmp .. "/src"
  assert(tmp, "Could not create a temporary directory")

  local installed
  local ok = Util.try(function()
    -- During the installation of a rock, luarocks can move a file from one place
    -- to another. Since that file originates from the Nix store, it has no
    -- write permission. Moving the file fails. The code below works around that
    -- by copying the entire rock source to a temporary dir and by making it writable.
    for name, path in pairs(rockspec_paths) do
      print("Building rock " .. name)
      local parent = vim.fs.dirname(path)
      local output, status = Process.exec({ "cp", "-r", parent, src })
      assert(status == 0, "Could not copy the source of rock " .. name .. ": " .. table.concat(output, "\n"))
      output, status = Process.exec({ "chmod", "-R", "u+w", src })
      assert(status == 0, "Could not make the source of rock " .. name .. " writable: " .. table.concat(output, "\n"))

      -- `luarocks make` uses the CWD as the source of the rock
      output, status = Process.exec({ "luarocks", "--tree", tree, "make" }, { cwd = src })
      assert(status == 0, "Could not build rock " .. name .. ":\n" .. table.concat(output, "\n"))

      -- Remove `src` so that it doesn't interfere with the next rock in the loop
      output, status = Process.exec({ "rm", "-r", src })
      assert(status == 0, "Could not remove the copied source of rock " .. name .. ": " .. table.concat(output, "\n"))
    end

    local lines, status = Process.exec({ "luarocks", "--tree", tree, "list", "--porcelain" })
    assert(status == 0, "Could not get a list of the installed rocks")
    table.remove(lines, #lines)

    installed = vim.tbl_map(function(line)
      local split = vim.split(line, "\t")
      return vim.list_slice(split, 1, 2)
    end, lines)
    return true
  end)

  Process.exec({ "rm", "-r", tmp })
  if not ok then
    error()
  end
  return pairs_to_dict(installed)
end

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

---@param rocks table<string, string>
local function prefetch_rocks(rocks)
  local out = {}
  for name, version in pairs(rocks) do
    if not vim.list_contains({ "git", "scm", "dev" }, version:sub(1, 3)) then
      print("Prefetching " .. name)
      out[name] = prefetch_src_rock(name, version)
    end
  end
  return out
end

---Prefetch all plugins and return their fetch data.
---@param opts? ManagerOpts
---@return table<string, FetchData>
function M.prefetch(opts)
  local out = {}
  local rockspecs = {}

  while true do
    local store_paths = {}
    local lazy_lua_specs = {}

    local plugins_to_do = {}
    for name, _ in pairs(Config.plugins) do
      if not out[name] then
        table.insert(plugins_to_do, name)
      end
    end

    local opts_with_default = Manage.opts(opts, {
      mode = "prefetch",
      clear = false,
      plugins = plugins_to_do,
    })
    Manage.run({
      pipeline = {
        "prefetch.version",
        { "prefetch.prefetch", out = out },
        { "prefetch.download", fetchData = out, store_paths = store_paths },
        { "prefetch.lazy_lua", store_paths = store_paths, specs = lazy_lua_specs },
        {
          "prefetch.rockspec",
          store_paths = store_paths,
          lazy_lua_specs = lazy_lua_specs,
          rockspecs = rockspecs,
        },
      },
    }, opts_with_default):wait()

    local lazy_lua_list = vim.tbl_values(lazy_lua_specs)
    if #lazy_lua_list > 0 then
      Config.spec:parse(lazy_lua_list)
    else
      for _, plugin in pairs(Config.plugins) do
        for _, task in ipairs(plugin._.tasks) do
          if task:has_errors() then
            error("An error occurred while prefetching")
          end
        end
      end

      local rocks = luarocks_dependencies(rockspecs)
      vim.print(prefetch_rocks(rocks))
      return { git = out, rocks = rocks }
    end
  end
end

return M
