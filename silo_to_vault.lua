-- Silo to Vault: moves everything from PULL_FROM to PUSH_TO,
-- except packages addressed to anything in SKIP_PACKAGES.

PULL_FROM = "create_connected:item_silo_18"
PUSH_TO = "create:item_vault_5"

-- Package addresses to leave behind (case-insensitive)
SKIP_PACKAGES = {
  "P1-Chest",
  "P1-Robo",
}

-- Seconds between checks when nothing moved
WAIT_TIME = 0.2


local skip = {}
for _, address in ipairs(SKIP_PACKAGES) do
  skip[string.lower(address)] = true
end

local totalMoved = 0
local totalSkipped = 0
local problem = nil

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
  if not string.find(item.name, "package", 1, true) then return false end
  local ok, detail = pcall(peripheral.call, PULL_FROM, "getItemDetail", slot)
  if not ok or not detail then return false end
  local address = getAddress(detail)
  if address and skip[string.lower(address)] then return true end
  if detail.displayName and skip[string.lower(detail.displayName)] then return true end
  return false
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
  print("Skipped: " .. totalSkipped .. " packages left behind")
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

-- Handle all slots in parallel so they land in the same tick.
local function moveOnce()
  local ok, items = pcall(peripheral.call, PULL_FROM, "list")
  if not ok or not items then
    problem = "Couldn't read " .. PULL_FROM
    return 0
  end

  local moved, skipped = 0, 0
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
        if n < item.count then problem = PUSH_TO .. " is full" end
      elseif not ok2 then
        problem = tostring(n)
      end
    end
  end
  if #tasks > 0 then parallel.waitForAll(table.unpack(tasks)) end

  totalMoved = totalMoved + moved
  totalSkipped = skipped
  return moved
end

while true do
  problem = check()
  if not problem then
    local moved = moveOnce()
    draw()
    if moved == 0 then sleep(WAIT_TIME) end
  else
    draw()
    sleep(2)
  end
end
