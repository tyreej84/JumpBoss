local Harness = dofile("tests/harness.lua")

local function joinLines(lines)
  if #lines == 0 then
    return "<none>"
  end
  return table.concat(lines, " | ")
end

local function requireLine(lines, needle, context)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return true
    end
  end
  error(context .. " missing line: " .. needle)
end

local function requireEqual(actual, expected, context)
  if actual ~= expected then
    error(string.format("%s expected %s, got %s", context, tostring(expected), tostring(actual)))
  end
end

local function printSection(title)
  print("")
  print("== " .. title .. " ==")
end

local function buildHarness(throttleMax)
  return Harness.new({
    addonPath = "JumpBoss.lua",
    groupMode = "RAID",
    throttleMax = throttleMax or 10,
    throttleRefill = 1,
    deliveryLatency = 0.02,
    -- Midnight/12.0: addon messages are locked while client.inCombat is true
    lockAddonMessagesInCombat = true,
  })
end

local function createRaid(harness)
  local clients = {
    harness:createClient({ name = "Alice", classFile = "MAGE" }),
    harness:createClient({ name = "Bob", classFile = "WARRIOR" }),
    harness:createClient({ name = "Cara", classFile = "PRIEST" }),
  }

  for _, client in ipairs(clients) do
    client:loadAddon()
    client:fireEvent("PLAYER_ENTERING_WORLD")
  end

  return clients
end

local function runLiveSyncScenario()
  local harness = buildHarness(10)
  local clients = createRaid(harness)
  local alice, bob, cara = clients[1], clients[2], clients[3]

  harness:broadcastEvent("ENCOUNTER_START", 301, "Training Boss")
  harness:advance(0.5)

  harness:setCombat(alice, true)
  harness:setCombat(bob, true)
  harness:setCombat(cara, true)

  alice:fireEvent("PLAYER_JUMP")
  harness:advance(1.0)
  bob:fireEvent("PLAYER_JUMP")
  harness:advance(0.4)
  bob:fireEvent("PLAYER_JUMP")
  harness:advance(0.4)
  cara:fireEvent("PLAYER_JUMP")
  harness:advance(4.5)

  -- Mid-combat: cross-player sync is blocked; each client only sees its own count
  local bobLinesMidCombat = bob:getVisibleLines()
  requireLine(bobLinesMidCombat, "Bob 2", "Bob UI mid-combat")

  printSection("Live Sync (mid-combat, sync blocked)")
  print("Bob UI:", joinLines(bobLinesMidCombat))
  print("Alice sends:", #alice.addonSends, "Bob sends:", #bob.addonSends, "Cara sends:", #cara.addonSends)

  harness:broadcastEvent("ENCOUNTER_END", 301, "Training Boss", 16, 3, 1)
  harness:advance(8.0)
  requireEqual(#alice.chatLog + #bob.chatLog + #cara.chatLog, 0, "chat while in combat")

  harness:setCombat(alice, false)
  harness:setCombat(bob, false)
  harness:setCombat(cara, false)
  -- The default post-combat safety delay is five seconds; allow the deferred
  -- winner post to flush after that protected-state settling window.
  harness:advance(11.5)

  -- Post-combat: sync converged; Bob now sees the full leaderboard
  local bobLinesPostCombat = bob:getVisibleLines()
  requireLine(bobLinesPostCombat, "Alice 1", "Bob UI post-combat")
  requireLine(bobLinesPostCombat, "Bob 2", "Bob UI post-combat")
  requireLine(bobLinesPostCombat, "Cara 1", "Bob UI post-combat")

  requireEqual(#alice.chatLog, 0, "Alice final chat count")
  requireEqual(#cara.chatLog, 0, "Cara final chat count")
  requireEqual(#bob.chatLog, 4, "Bob final chat count")

  printSection("Post Combat Chat")
  for index, entry in ipairs(bob.chatLog) do
    print(index .. ".", entry.chatType, entry.message)
  end
end

local function runThrottleScenario()
  local harness = buildHarness(2)
  local clients = createRaid(harness)
  local alpha, beta = clients[1], clients[2]

  harness:broadcastEvent("ENCOUNTER_START", 302, "Throttle Boss")
  harness:advance(0.25)
  harness:setCombat(alpha, true)
  harness:setCombat(beta, true)

  alpha:fireEvent("PLAYER_JUMP")
  harness:advance(0.25)
  alpha:fireEvent("PLAYER_JUMP")
  harness:advance(0.25)
  alpha:fireEvent("PLAYER_JUMP")
  harness:advance(5.0)

  -- Leave combat so queued comms flush and beta can receive alpha's final count
  harness:setCombat(alpha, false)
  harness:setCombat(beta, false)
  harness:advance(2.0)

  local betaLines = beta:getVisibleLines()
  requireLine(betaLines, "Alice 3", "Throttle UI")

  printSection("Throttle Recovery")
  print("Beta UI:", joinLines(betaLines))
  print("Alpha addon sends:", #alpha.addonSends)
end

local ok, err = pcall(function()
  runLiveSyncScenario()
  runThrottleScenario()
end)

if not ok then
  io.stderr:write("Simulation failed: " .. tostring(err) .. "\n")
  if os.exit then
    os.exit(1)
  end
  error(err)
end

print("\nAll simulation scenarios passed.")
