-- Silo to Vault: moves everything from PULL_FROM to PUSH_TO,
-- except packages addressed to anything in SKIP_PACKAGES and items in SKIP_ITEMS.

PULL_FROM = "create_connected:item_silo_18"
PUSH_TO = "create:item_vault_5"

-- Package addresses to leave behind (case-insensitive)
SKIP_PACKAGES = {
  "P1-Chest",
  "P1-Robo",
}

-- Item IDs to leave behind (shown with F3+H on the tooltip, e.g. "minecraft:diamond")
SKIP_ITEMS = {
}

-- Seconds to wait when nothing moved (0 = as fast as possible)
WAIT_TIME = 0
AUTO_UPDATE = true        -- install new versions from GitHub automatically, keeping these settings

-- Settings in /config.lua override the ones above. Use it for anything you
-- don't want to retype: it survives reinstalls and updates, and one file can
-- be shared by every computer (each program ignores settings it doesn't use).
do
  local path = "/config.lua"
  if fs.exists(path) then
    local fn, err = loadfile(path, "t", _ENV)
    if fn then
      local ok, runErr = pcall(fn)
      if not ok then printError("config.lua: " .. tostring(runErr)) sleep(3) end
    else
      printError("config.lua: " .. tostring(err))
      sleep(3)
    end
  end
end


local skip = {}
for _, address in ipairs(SKIP_PACKAGES) do
  skip[string.lower(address)] = true
end

local skipItem = {}
for _, id in ipairs(SKIP_ITEMS) do
  skipItem[string.lower(id)] = true
end

local totalMoved = 0
local totalSkipped = 0
local problem = nil

-- Skip decisions keyed by the item's component hash, so each package
-- is only inspected once instead of on every pass.
local skipCache = {}
local cacheSize = 0

-- Create adds a "package" entry to item details for cardboard packages.
local function getAddress(detail)
  local pkg = detail and detail.package
  if type(pkg) ~= "table" then return nil end
  if type(pkg.getAddress) == "function" then
    local ok, address = pcall(pkg.getAddress)
    if ok then return address end
  end
  return pkg.address
end

local function shouldSkip(slot, item)
  if skipItem[item.name] then return true end
  if not string.find(item.name, "package", 1, true) then return false end
  local key = item.nbt
  if key and skipCache[key] ~= nil then return skipCache[key] end

  local ok, detail = pcall(peripheral.call, PULL_FROM, "getItemDetail", slot)
  if not ok or not detail then return false end
  local address = getAddress(detail)
  local result = (address ~= nil and skip[string.lower(address)] == true)
    or (detail.displayName ~= nil and skip[string.lower(detail.displayName)] == true)

  if key then
    if cacheSize > 5000 then
      skipCache, cacheSize = {}, 0
    end
    skipCache[key] = result
    cacheSize = cacheSize + 1
  end
  return result
end

-- pushItems can't cross separate cable networks, even if the computer sees both.
local function sameNetwork()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "peripheral_hub") then
      local hasPull = peripheral.call(side, "isPresentRemote", PULL_FROM)
      local hasPush = peripheral.call(side, "isPresentRemote", PUSH_TO)
      if hasPull and hasPush then return true end
    end
  end
  return false
end

local function check()
  if not peripheral.isPresent(PULL_FROM) then
    return "Can't find PULL_FROM: " .. PULL_FROM
  end
  if not peripheral.isPresent(PUSH_TO) then
    return "Can't find PUSH_TO: " .. PUSH_TO
  end
  if not sameNetwork() then
    return "PULL_FROM and PUSH_TO are on different cables. Connect the cables together."
  end
  return nil
end

local function draw()
  term.clear()
  term.setCursorPos(1, 1)
  print("Silo to Vault")
  print("")
  print("From:    " .. PULL_FROM)
  print("To:      " .. PUSH_TO)
  print("Moved:   " .. totalMoved .. " items")
  print("Skipped: " .. totalSkipped .. " stacks left behind")
  print("")
  if problem then
    if term.isColour() then term.setTextColour(colours.red) end
    print("PROBLEM: " .. problem)
    term.setTextColour(colours.white)
  else
    if term.isColour() then term.setTextColour(colours.lime) end
    print("Running")
    term.setTextColour(colours.white)
  end
end

-- One pass: list the source, then push every slot in parallel so all
-- pushes land in the same tick. Returns items moved and whether a call
-- failed (meaning the setup should be re-checked).
local function moveOnce()
  local ok, items = pcall(peripheral.call, PULL_FROM, "list")
  if not ok or not items then
    return 0, "Couldn't read " .. PULL_FROM
  end

  local moved, skipped = 0, 0
  local full, failed = false, nil
  local tasks = {}
  for slot, item in pairs(items) do
    tasks[#tasks + 1] = function()
      if shouldSkip(slot, item) then
        skipped = skipped + 1
        return
      end
      local ok2, n = pcall(peripheral.call, PULL_FROM, "pushItems", PUSH_TO, slot)
      if ok2 and n then
        moved = moved + n
        if n < item.count then full = true end
      elseif not ok2 then
        failed = tostring(n)
      end
    end
  end
  if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end

  totalMoved = totalMoved + moved
  totalSkipped = skipped
  if failed then return moved, failed end
  problem = full and (PUSH_TO .. " is full") or nil
  return moved, nil
end

local function worker()
  while true do
    problem = check()
    if problem then
      sleep(2)
    else
      while true do
        local moved, err = moveOnce()
        if err then
          problem = err
          sleep(1)
          break
        end
        if moved == 0 and WAIT_TIME > 0 then sleep(WAIT_TIME) end
      end
    end
  end
end

-- Redraw on a timer rather than every pass.
local function screen()
  while true do
    draw()
    sleep(0.5)
  end
end

local function readyToUpdate()
  return true
end

-- ============================================================ auto-update

-- Every UPDATE_CHECK_MINUTES this checks GitHub for a newer version. A new
-- version is downloaded, checked that it loads, given your current settings
-- (the UPPERCASE lines at the top of this file), saved, and the computer
-- reboots into it. Set AUTO_UPDATE = false at the top to turn this off.
local UPDATE_REPO = "levisnakes/cc-silo-to-vault"
local UPDATE_FILE = "silo_to_vault.lua"
local UPDATE_CHECK_MINUTES = 15
local PROGRAM_PATH = (shell and shell.getRunningProgram()) or "startup.lua"
local SHA_FILE = "/.version_" .. UPDATE_FILE

-- Settings are the top-of-file assignments to UPPERCASE names, before the
-- first "local" line or "-- ====" section. Tables can span several lines.
local function splitSettings(src)
  local settings, rest = {}, {}
  local inSettings = true
  for line in (src .. "\n"):gmatch("(.-)\n") do
    if inSettings and (line:match("^local ") or line:match("^%-%- ====")) then inSettings = false end
    table.insert(inSettings and settings or rest, line)
  end
  return settings, rest
end

local function braceDelta(line)
  local code = line:gsub('"[^"]*"', ""):gsub("%-%-.*$", "")
  local _, opens = code:gsub("{", "")
  local _, closes = code:gsub("}", "")
  return opens - closes
end

-- [NAME] = the full statement text, possibly several lines
local function statements(lines)
  local out = {}
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^([%u_][%u%d_]*)%s*=")
    if name then
      local block = { lines[i] }
      local depth = braceDelta(lines[i])
      while depth > 0 and i < #lines do
        i = i + 1
        table.insert(block, lines[i])
        depth = depth + braceDelta(lines[i])
      end
      out[name] = table.concat(block, "\n")
    end
    i = i + 1
  end
  return out
end

-- New file, with each setting that already exists replaced by your value.
local function mergeSettings(oldSrc, newSrc)
  local oldSettings = statements((splitSettings(oldSrc)))
  local newSettings, rest = splitSettings(newSrc)
  local out = {}
  local i = 1
  while i <= #newSettings do
    local line = newSettings[i]
    local name = line:match("^([%u_][%u%d_]*)%s*=")
    if name and oldSettings[name] then
      table.insert(out, oldSettings[name])
      local depth = braceDelta(line)
      while depth > 0 and i < #newSettings do
        i = i + 1
        depth = depth + braceDelta(newSettings[i])
      end
    else
      table.insert(out, line)
    end
    i = i + 1
  end
  for _, line in ipairs(rest) do table.insert(out, line) end
  local merged = table.concat(out, "\n")
  -- splitting added one trailing newline's worth of empty line; match the source
  if newSrc:sub(-1) == "\n" and merged:sub(-1) ~= "\n" then merged = merged .. "\n" end
  return (merged:gsub("\n\n$", "\n"))
end

local function fetch(url, headers)
  local ok, h = pcall(http.get, url, headers)
  if not ok or not h then return nil end
  local body = h.readAll()
  h.close()
  return body
end

local function readText(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local t = f.readAll()
  f.close()
  return t
end

local function writeText(path, text)
  local f = fs.open(path, "w")
  f.write(text)
  f.close()
end

local function checkForUpdate(atBoot)
  if AUTO_UPDATE == false or not http then return end
  local sha = fetch("https://api.github.com/repos/" .. UPDATE_REPO .. "/commits/main",
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-auto-update" })
  if not sha then return end
  sha = sha:match("^%s*(%x+)%s*$")
  if not sha or #sha < 40 or readText(SHA_FILE) == sha then return end

  local newSrc = fetch("https://raw.githubusercontent.com/" .. UPDATE_REPO .. "/" .. sha .. "/" .. UPDATE_FILE)
  if not newSrc or not _G.load(newSrc, UPDATE_FILE) then return end
  local oldSrc = readText(PROGRAM_PATH)
  if not oldSrc then return end
  local merged = mergeSettings(oldSrc, newSrc)
  if not _G.load(merged, UPDATE_FILE) then return end
  if merged == oldSrc then
    writeText(SHA_FILE, sha)
    return
  end

  -- at boot nothing is running yet, so there is nothing to wait for
  while not atBoot and not readyToUpdate() do sleep(5) end
  writeText(PROGRAM_PATH .. ".old", oldSrc)
  writeText(PROGRAM_PATH, merged)
  writeText(SHA_FILE, sha)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Updated to " .. sha:sub(1, 7) .. ", restarting...")
  if not atBoot then sleep(1) end
  os.reboot()
end

local function updateLoop()
  while true do
    sleep(UPDATE_CHECK_MINUTES * 60)
    pcall(checkForUpdate)
  end
end

-- Check for a new version as soon as the computer starts, before the
-- program runs, so a restart always picks up the latest version.
local function bootUpdate()
  if AUTO_UPDATE == false or not http then return end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Checking for updates...")
  pcall(checkForUpdate, true)
end

bootUpdate()
parallel.waitForAny(worker, screen, updateLoop)
