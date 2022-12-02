local Util = require("lazy.core.util")
local Config = require("lazy.core.config")

local M = {}

---@type LazyPlugin[]
M.loading = {}
M.init_done = false

function M.setup()
  -- install missing plugins
  if Config.options.install_missing then
    Util.track("install")
    for _, plugin in pairs(Config.plugins) do
      if not plugin._.installed then
        vim.cmd("do User LazyInstallPre")
        require("lazy.manage").install({ wait = true })
        break
      end
    end
    Util.track()
  end

  -- setup handlers
  Util.track("handlers")
  local Handler = require("lazy.core.handler")
  Handler.setup()
  Util.track()

  -- autoload opt plugins
  table.insert(package.loaders, M.autoload)
end

function M.init_plugins()
  Util.track("loader")
  Util.track({ start = "init" })
  for _, plugin in pairs(Config.plugins) do
    if plugin.init then
      Util.track({ plugin = plugin.name, init = "init" })
      Util.try(plugin.init, "Failed to run `init` for **" .. plugin.name .. "**")
      Util.track()
    end
    if plugin.lazy == false then
      M.load(plugin, { start = "startup" })
    end
  end
  Util.track()
  Util.track()
  M.init_done = true
end

---@class Loader
---@param plugins string|LazyPlugin|string[]|LazyPlugin[]
---@param reason {[string]:string}
function M.load(plugins, reason)
  ---@diagnostic disable-next-line: cast-local-type
  plugins = (type(plugins) == "string" or plugins.name) and { plugins } or plugins
  ---@cast plugins (string|LazyPlugin)[]

  for _, plugin in ipairs(plugins) do
    plugin = type(plugin) == "string" and Config.plugins[plugin] or plugin
    ---@cast plugin LazyPlugin

    if not plugin._.loaded then
      ---@diagnostic disable-next-line: assign-type-mismatch
      plugin._.loaded = {}
      for k, v in pairs(reason) do
        plugin._.loaded[k] = v
      end
      if #M.loading > 0 then
        plugin._.loaded.plugin = M.loading[#M.loading].name
      elseif reason.require then
        plugin._.loaded.source = Util.get_source()
      end

      table.insert(M.loading, plugin)

      Util.track({ plugin = plugin.name, start = reason.start })

      vim.opt.runtimepath:prepend(plugin.dir)

      if plugin.dependencies then
        M.load(plugin.dependencies, {})
      end

      M.packadd(plugin)
      if plugin.config then
        Util.try(plugin.config, "Failed to run `config` for " .. plugin.name)
      end

      plugin._.loaded.time = Util.track().time
      table.remove(M.loading)
      vim.schedule(function()
        vim.cmd("do User LazyRender")
      end)
    end
  end
end

---@param plugin LazyPlugin
function M.packadd(plugin)
  -- FIXME: investigate further what else is needed
  -- vim.cmd.packadd(plugin.name)
  -- M.source_runtime(plugin, "/after/plugin")
  if M.init_done then
    M.source_runtime(plugin, "/plugin")
    if vim.g.did_load_filetypes == 1 then
      M.source_runtime(plugin, "/ftdetect")
    end
    M.source_runtime(plugin, "/after/plugin")
  end
end

---@param plugin LazyPlugin
---@param dir? string
function M.source_runtime(plugin, dir)
  Util.walk(plugin.dir .. dir, function(path, _, t)
    local ext = path:sub(-3)
    if t == "file" and (ext == "lua" or ext == "vim") then
      vim.cmd("silent source " .. path)
    end
  end)
end

-- This loader is added as the very last one.
-- This only hits when the modname is not cached and
-- even then only once per plugin. So pretty much never.
--
-- lazy.module will call this when loading a cached file with modpath set.
---@param modname string
---@param modpath string?
function M.autoload(modname, modpath)
  -- fast return when we know the modpath
  if modpath then
    local plugin = require("lazy.core.plugin").find(modpath)
    if plugin and not plugin._.loaded then
      M.load(plugin, { require = modname })
    end
    return
  end
  -- check if a lazy plugin should be loaded
  for _, plugin in pairs(Config.plugins) do
    if not plugin._.loaded then
      for _, pattern in ipairs({ ".lua", "/init.lua" }) do
        local path = plugin.dir .. "/lua/" .. modname:gsub("%.", "/") .. pattern
        if vim.loop.fs_stat(path) then
          M.load(plugin, { require = modname })
          local chunk, err = loadfile(path)
          return chunk or error(err)
        end
      end
    end
  end
  return modname .. " not found in unloaded opt plugins"
end

return M
