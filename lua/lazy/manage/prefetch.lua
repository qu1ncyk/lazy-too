local Config = require("lazy.core.config")
local Manage = require("lazy.manage")
local Process = require("lazy.manage.process")
local Util = require("lazy.core.util")

local M = {}

---Prefetch all plugins and return their fetch data.
---@param opts? ManagerOpts
---@return table<string, FetchData>
function M.prefetch(opts)
  local out = {}
  local rockspecs = {}
  local rockspec_deps = {}
  local rock_data = {}

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
        { "prefetch.rockspec_deps", rockspecs = rockspecs, rockspec_deps = rockspec_deps },
        { "prefetch.rockspec_download_deps", rockspec_deps = rockspec_deps, rock_data = rock_data },
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

      vim.print(rockspec_deps)
      return { git = out, rocks = rock_data }
    end
  end
end

return M
