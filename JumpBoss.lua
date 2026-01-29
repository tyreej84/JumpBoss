-- JumpBoss.lua
-- Real-time jump leaderboard during boss encounters (addon users only).
-- Silent addon comms during encounter, ZERO chat until encounter end.
-- At end: ONLY the winner posts the leaderboard.
--
-- v1.0.7 drop-in replacement fixes:
--  - Only ONE person posts at end (robust claim arbitration; prevents multiple winners posting)
--  - Jump counting stops immediately when the boss dies (phase state machine)
--  - Waits ~5 seconds to sync totals before determining winner
--  - Chat always includes at least Top 5 (or fewer if fewer participants)
--  - Leaderboard remains visible ~20 seconds after boss death (display only; no counting)
--  - Accepts updates while encounter UI is active even if encounter IDs mismatch (reload/missed ENCOUNTER_START)
--  - Spacing between "You: X" and rows, class color fallback

local ADDON_NAME = ...
local PREFIX = "JBT1"

local f = CreateFrame("Frame")
local db

-- -----------------------------
-- Defaults
-- -----------------------------
local DEFAULTS = {
  show = true,
  locked = false,
  scale = 1.0,

  maxLines = 5,               -- UI: Top 5
  width = 150,
  lineHeight = 13,

  broadcastInterval = 0.10,
  heartbeatInterval = 1.25,

  staleTimeout = 120.0,
  fadeDuration = 10.0,

  syncWindow = 5.0,           -- seconds after ENCOUNTER_END to sync totals
  claimPostDelay = 1.00,      -- IMPORTANT: allow time for other claims to arrive before posting
  postVisibleSeconds = 20.0,  -- keep UI visible after boss death

  postTopN = 5,               -- min top N in chat (or fewer if fewer total)

  pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 160 },
}

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function Now() return GetTime() or 0 end

local function PlayerFullName()
  local name, realm = UnitName("player")
  realm = realm or GetRealmName() or ""
  if realm ~= "" and not name:find("-") then
    return name .. "-" .. realm
  end
  return name
end

local function InGroupChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function Clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

-- -----------------------------
-- State
-- -----------------------------
-- phase: "idle" (no encounter), "active" (counting), "ended" (frozen, syncing + displaying)
local phase = "idle"
local encounterID = 0
local encounterName = ""

local myName = ""
local myClass = ""
local myJumps = 0

local totals = {}      -- name -> jumps
local lastSeen = {}    -- name -> timestamp
local classByName = {} -- name -> classFile

local lastBroadcastAt = 0
local lastHeartbeatAt = 0
local pendingBroadcast = false

local claimWinner = nil
local lastJumpAt = 0

-- -----------------------------
-- UI
-- -----------------------------
local ui = CreateFrame("Frame", "JumpBossFrame", UIParent, "BackdropTemplate")
ui:SetClampedToScreen(true)
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", function(self)
  if not db.locked then self:StartMoving() end
end)
ui:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relPoint, x, y = self:GetPoint(1)
  db.pos.point, db.pos.relPoint, db.pos.x, db.pos.y = point, relPoint, x, y
end)

ui:SetBackdrop({
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = nil,
  tile = true, tileSize = 16, edgeSize = 0,
  insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
ui:SetBackdropColor(0, 0, 0, 0.55)

ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ui.title:SetPoint("TOPLEFT", 6, -5)
ui.title:SetText("JumpBoss")

ui.sub = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ui.sub:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -1)
ui.sub:SetText("Not in encounter")

ui.lines = {}

local function ResizeUI()
  local lines = db.maxLines or DEFAULTS.maxLines
  local lineH = db.lineHeight or DEFAULTS.lineHeight
  local w = db.width or DEFAULTS.width

  local headerH = 26
  local h = headerH + (lines * lineH) + 6
  ui:SetSize(w, h)

  for i = 1, lines do
    if not ui.lines[i] then
      ui.lines[i] = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    local fs = ui.lines[i]
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 6, -(headerH + (i - 1) * lineH))
    fs:SetText("")
    fs:SetAlpha(1)
    fs:Show()
  end

  for i = lines + 1, #ui.lines do
    ui.lines[i]:SetText("")
    ui.lines[i]:Hide()
  end
end

local function ApplyUISettings()
  ui:SetScale(db.scale or 1.0)
  ui:ClearAllPoints()
  ui:SetPoint(db.pos.point, UIParent, db.pos.relPoint, db.pos.x, db.pos.y)
  ui:SetShown(db.show)
  ResizeUI()
end

local function NameColor(name)
  local classFile = classByName[name]
  if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

local function BuildSortedVisibleTotals()
  local t = Now()
  local timeout = db.staleTimeout or DEFAULTS.staleTimeout
  local fade = db.fadeDuration or DEFAULTS.fadeDuration

  local arr = {}
  for name, count in pairs(totals) do
    if type(count) == "number" then
      local seen = lastSeen[name]
      if seen then
        local age = t - seen
        if age <= (timeout + fade) then
          table.insert(arr, { name = name, count = count, age = age })
        end
      end
    end
  end

  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  return arr
end

local function UpdateUI()
  if not db.show then return end

  if phase == "idle" then
    ui.sub:SetText("Not in encounter")
    for i = 1, (db.maxLines or DEFAULTS.maxLines) do
      if ui.lines[i] then
        ui.lines[i]:SetText("")
        ui.lines[i]:SetAlpha(1)
      end
    end
    return
  end

  ui.sub:SetText(string.format("You: %d", myJumps))

  local arr = BuildSortedVisibleTotals()
  local lines = db.maxLines or DEFAULTS.maxLines
  local timeout = db.staleTimeout or DEFAULTS.staleTimeout
  local fade = db.fadeDuration or DEFAULTS.fadeDuration

  for i = 1, lines do
    local fs = ui.lines[i]
    local row = arr[i]

    if row then
      local alpha = 1
      if row.age > timeout then
        alpha = 1 - ((row.age - timeout) / math.max(0.01, fade))
        alpha = Clamp(alpha, 0, 1)
      end

      local r, g, b = NameColor(row.name)
      fs:SetText(string.format("%d. %s %d", i, row.name, row.count))
      fs:SetTextColor(r, g, b, 1)
      fs:SetAlpha(alpha)
    else
      fs:SetText("")
      fs:SetAlpha(1)
    end
  end
end

-- -----------------------------
-- Addon comms
-- -----------------------------
local function SendComm(msg)
  local ch = InGroupChannel()
  if not ch then return end
  C_ChatInfo.SendAddonMessage(PREFIX, msg, ch)
end

local function BroadcastUpdate(force)
  if phase ~= "active" then return end
  local t = Now()

  if not force then
    if (t - lastBroadcastAt) < (db.broadcastInterval or DEFAULTS.broadcastInterval) then
      pendingBroadcast = true
      return
    end
  end

  pendingBroadcast = false
  lastBroadcastAt = t
  SendComm(string.format("U:%d:%d:%s", encounterID, myJumps, myClass or ""))
end

local function Heartbeat()
  if phase ~= "active" then return end
  local t = Now()
  if (t - lastHeartbeatAt) < (db.heartbeatInterval or DEFAULTS.heartbeatInterval) then return end
  lastHeartbeatAt = t
  SendComm(string.format("H:%d:%d:%s", encounterID, myJumps, myClass or ""))
end

local function SendClaim()
  -- C:<encounterID>:<winnerName>:<count>
  SendComm(string.format("C:%d:%s:%d", encounterID, myName, myJumps))
end

-- -----------------------------
-- Jump detection (ONLY during "active")
-- -----------------------------
hooksecurefunc("JumpOrAscendStart", function()
  if phase ~= "active" then return end
  if UnitInVehicle("player") or UnitOnTaxi("player") then return end

  local t = Now()
  if (t - lastJumpAt) < 0.08 then return end
  lastJumpAt = t

  myJumps = myJumps + 1
  totals[myName] = myJumps
  lastSeen[myName] = t
  classByName[myName] = myClass

  BroadcastUpdate(false)
  UpdateUI()
end)

-- -----------------------------
-- Posting helpers
-- -----------------------------
local function BuildSortedTotalsAll()
  local arr = {}
  for name, count in pairs(totals) do
    if type(count) == "number" then
      table.insert(arr, { name = name, count = count })
    end
  end
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  return arr
end

local function AmIWinnerByTotals()
  local arr = BuildSortedTotalsAll()
  if #arr == 0 then return false end

  local maxCount = arr[1].count or 0
  if myJumps ~= maxCount then return false end

  -- tie-break alphabetically among maxCount
  local best = nil
  for _, row in ipairs(arr) do
    if row.count ~= maxCount then break end
    if not best or row.name < best then best = row.name end
  end
  return best == myName
end

local function BuildChatLines()
  local arr = BuildSortedTotalsAll()
  local boss = encounterName ~= "" and encounterName or "Boss"
  local total = #arr

  local lines = {}
  table.insert(lines, string.format("Jump Leaderboard - %s", boss))

  if total == 0 then
    table.insert(lines, "No JumpBoss participants recorded.")
    return lines
  end

  local configured = tonumber(db.postTopN or DEFAULTS.postTopN or 5) or 5
  if configured < 5 then configured = 5 end
  local topN = math.min(configured, total)

  local current = ""
  local function flush()
    if current ~= "" then
      table.insert(lines, current)
      current = ""
    end
  end

  for i = 1, topN do
    local row = arr[i]
    local chunk = string.format("%d)%s(%d)", i, row.name, row.count)
    if current == "" then
      current = chunk
    else
      local candidate = current .. " | " .. chunk
      if #candidate > 240 then
        flush()
        current = chunk
      else
        current = candidate
      end
    end
  end
  flush()

  table.insert(lines, "(Counts only players with JumpBoss.)")
  return lines
end

local function PostToChat(lines)
  local ch = InGroupChannel()
  if not ch then return end
  for _, line in ipairs(lines) do
    SendChatMessage(line, ch)
  end
end

local function HandleEncounterEndPosting()
  local window = db.syncWindow or DEFAULTS.syncWindow
  local postDelay = db.claimPostDelay or DEFAULTS.claimPostDelay

  C_Timer.After(window, function()
    if claimWinner then return end
    if not AmIWinnerByTotals() then return end

    -- CRITICAL: assume we are the claimant locally immediately,
    -- so we don't post before we receive competing claims.
    claimWinner = myName
    SendClaim()

    C_Timer.After(postDelay, function()
      -- If we saw another claim from a "better" winner, do not post.
      if claimWinner ~= myName then return end
      PostToChat(BuildChatLines())
    end)
  end)
end

-- -----------------------------
-- Lifecycle
-- -----------------------------
local function BeginEncounter(newID, newName)
  phase = "active"
  encounterID = newID or 0
  encounterName = newName or "Encounter"

  myJumps = 0
  wipe(totals)
  wipe(lastSeen)
  wipe(classByName)

  totals[myName] = 0
  lastSeen[myName] = Now()
  classByName[myName] = myClass

  lastBroadcastAt = 0
  lastHeartbeatAt = 0
  pendingBroadcast = false
  claimWinner = nil

  BroadcastUpdate(true)
  UpdateUI()
end

local function FreezeEncounter(encIDFromEvent)
  -- Freeze counting immediately; keep UI up
  phase = "ended"
  pendingBroadcast = false

  -- Heal encounterID if missed ENCOUNTER_START (reload mid-fight)
  if encounterID == 0 or encounterID ~= encIDFromEvent then
    encounterID = encIDFromEvent or encounterID
    if encounterName == "" then encounterName = "Encounter" end
  end

  totals[myName] = myJumps
  lastSeen[myName] = Now()
  classByName[myName] = myClass

  -- Final broadcast of our frozen count
  SendComm(string.format("U:%d:%d:%s", encounterID, myJumps, myClass or ""))

  UpdateUI()
end

local function EndEncounterUI()
  phase = "idle"
  UpdateUI()
end

-- -----------------------------
-- Event handlers
-- -----------------------------
local function NormalizeSender(sender)
  sender = sender or ""
  if sender ~= "" and not sender:find("-") then
    local realm = GetRealmName() or ""
    if realm ~= "" then sender = sender .. "-" .. realm end
  end
  return sender
end

local function OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= PREFIX then return end
  if type(msg) ~= "string" then return end

  sender = NormalizeSender(sender)
  if sender == "" then return end

  local tag, a, b, c = string.match(msg, "^(%a):([^:]+):([^:]+):?(.*)$")
  if not tag then return end

  if tag == "U" or tag == "H" then
    local enc = tonumber(a)
    local count = tonumber(b)
    local classFile = c
    if not enc or not count then return end
    if phase == "idle" then return end

    -- While encounter UI is active (active OR ended), accept updates even if enc differs
    totals[sender] = count
    lastSeen[sender] = Now()
    if classFile and classFile ~= "" then
      classByName[sender] = classFile
    end

    UpdateUI()
    return
  end

  if tag == "C" then
    local enc = tonumber(a)
    local winnerName = b
    local winnerCount = tonumber(c)
    if not enc or not winnerName or winnerName == "" or not winnerCount then return end
    if enc ~= encounterID then return end

    -- Robust arbitration: keep the alphabetically smallest claimed winner.
    -- (All claimers should only claim when they believe they are top by totals.)
    if not claimWinner or winnerName < claimWinner then
      claimWinner = winnerName
    end
    return
  end
end

local function SlashHelp()
  print("|cffffd100JumpBoss commands:|r")
  print("/jb show | hide")
  print("/jb lock | unlock")
  print("/jb scale <n>")
  print("/jb timeout <s>")
  print("/jb fade <s>")
  print("/jb top <n>  (chat posts at least top 5)")
end

SLASH_JUMPBOSS1 = "/jumpboss"
SLASH_JUMPBOSS2 = "/jb"
SlashCmdList.JUMPBOSS = function(msg)
  msg = (msg or "")
  local lower = msg:lower()

  if lower == "show" then
    db.show = true
    ui:Show()
    UpdateUI()
    return
  elseif lower == "hide" then
    db.show = false
    ui:Hide()
    return
  elseif lower == "lock" then
    db.locked = true
    print("JumpBoss: frame locked.")
    return
  elseif lower == "unlock" then
    db.locked = false
    print("JumpBoss: frame unlocked (drag to move).")
    return
  end

  local cmd, val = lower:match("^(%S+)%s*(.*)$")
  if cmd == "scale" and val ~= "" then
    local n = tonumber(val)
    if n and n > 0.2 and n < 3.0 then
      db.scale = n
      ApplyUISettings()
      print(("JumpBoss: scale set to %.2f"):format(n))
      return
    end
  elseif cmd == "timeout" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 0.5 and n <= 300 then
      db.staleTimeout = n
      print(("JumpBoss: stale timeout set to %.1fs"):format(n))
      return
    end
  elseif cmd == "fade" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 0.2 and n <= 60 then
      db.fadeDuration = n
      print(("JumpBoss: fade duration set to %.1fs"):format(n))
      return
    end
  elseif cmd == "top" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 5 and n <= 50 then
      db.postTopN = math.floor(n)
      print(("JumpBoss: chat top N set to %d (min 5)"):format(db.postTopN))
      return
    else
      print("JumpBoss: /jb top must be between 5 and 50.")
      return
    end
  end

  SlashHelp()
end

f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end

    myName = PlayerFullName()
    local _, classFile = UnitClass("player")
    myClass = classFile or ""

    JumpBossDB = JumpBossDB or {}
    db = JumpBossDB
    CopyDefaults(db, DEFAULTS)

    if type(db.postTopN) == "number" and db.postTopN < 5 then db.postTopN = 5 end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    ApplyUISettings()
    UpdateUI()
    return
  end

  if event == "CHAT_MSG_ADDON" then
    OnAddonMessage(...)
    return
  end

  if event == "ENCOUNTER_START" then
    local encID, encName = ...
    BeginEncounter(encID, encName)
    return
  end

  if event == "ENCOUNTER_END" then
    local encID = ...
    if phase ~= "idle" then
      FreezeEncounter(encID)
      HandleEncounterEndPosting()
      C_Timer.After(db.postVisibleSeconds or DEFAULTS.postVisibleSeconds, EndEncounterUI)
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    UpdateUI()
    return
  end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

ui:SetScript("OnUpdate", function(self, elapsed)
  if phase == "idle" then return end

  if phase == "active" then
    if pendingBroadcast then
      BroadcastUpdate(false)
    end
    Heartbeat()
  end

  UpdateUI()
end)
