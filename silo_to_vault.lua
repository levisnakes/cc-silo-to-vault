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

parallel.waitForAny(worker, screen)
