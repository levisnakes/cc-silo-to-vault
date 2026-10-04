-- =============================================================
--  SILO TO VAULT
--  Moves everything from one storage block into another,
--  but leaves behind packages sent to the addresses below.
-- =============================================================
--
--  HOW TO CHANGE SETTINGS
--  Only edit the lines in the SETTINGS box below.
--  Keep the quote marks " " around every name.
--
--  To find a block's name: right-click the wired modem on it.
--  Chat will say something like:
--      Peripheral "create:item_vault_2" connected to network
--  The part in quotes is the name to type here.
--
-- ======================== SETTINGS ===========================

-- Take items OUT of this block:
PULL_FROM = "create_connected:item_silo_18"

-- Put items INTO this block:
PUSH_TO = "create:item_vault_5"

-- Packages sent to these addresses are NOT moved.
-- One address per line, in quotes, with a comma at the end.
-- Capital letters don't matter.
SKIP_PACKAGES = {
  "P1-Chest",
  "P1-Robo",
}

-- How long to wait (in seconds) before checking again when
-- there was nothing to move. Smaller = faster, but more lag.
WAIT_TIME = 0.2

-- ===================== END OF SETTINGS =======================
-- You don't need to change anything below this line.


local skip = {}
for _, address in ipairs(SKIP_PACKAGES) do
  skip[string.lower(address)] = true
end

local totalMoved = 0
local totalSkipped = 0
local problem = nil

-- Read the delivery address of a package. Create adds a "package"
-- entry to the item details for every cardboard package.
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
  -- Only packages can be skipped; normal items always move.
  if not string.find(item.name, "package", 1, true) then return false end
  local ok, detail = pcall(peripheral.call, PULL_FROM, "getItemDetail", slot)
  if not ok or not detail then return false end
  local address = getAddress(detail)
  if address and skip[string.lower(address)] then return true end
  -- Also catch packages renamed in an anvil.
  if detail.displayName and skip[string.lower(detail.displayName)] then return true end
  return false
end

-- Are both blocks on the same cable? Items can't move between
-- two separate cable networks, even if the computer sees both.
local function sameNetwork()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "peripheral_hub") then
      local hasPull = peripheral.call(side, "isPresentRemote", PULL_FROM)
      local hasPush = peripheral.call(side, "isPresentRemote", PUSH_TO)
      if hasPull and hasPush then return true end
    end
  end
  -- Blocks touching the computer directly can't reach each other either.
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

-- One pass over every slot. Slots are handled at the same time
-- so a full silo empties in a few ticks instead of one slot per tick.
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
