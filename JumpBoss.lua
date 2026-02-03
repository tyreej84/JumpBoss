-- JumpBoss.lua
-- v1.2.5
--
-- Fixes:
--  - FIX live updates: choose RAID first (prevents RAID vs INSTANCE_CHAT split)
--  - Keeps: C_ChatInfo.SendChatMessage for taint avoidance
--  - Keeps: hard-sanitize '|' to '||' to prevent "Invalid escape code"
--  - Keeps: winner-only posting with POSTED lock + deterministic stagger

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

  maxLines = 5,
  width = 160,
  lineHeight = 13,

  broadcastInterval = 0.10,
  heartbeatInterval = 1.25,

  staleTimeout = 120.0,
  fadeDuration = 10.0,

  syncWindow = 5.0,
  claimPostDelay = 1.00,
  postVisibleSeconds = 20.0,

  postTopN = 5, -- min 5 enforced

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
  if realm ~= "" and name and not name:find("-") then
    return name .. "-" .. realm
  end
  return name or ""
end

local function ShortName(full)
  if not full or full == "" then return "" end
  return Ambiguate(full, "short")
end

local function Clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

-- IMPORTANT:
-- Prefer RAID first so everyone in a raid uses the same channel.
-- Then INSTANCE_CHAT for LFG/instance parties, then PARTY.
local function GetGroupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInGroup() then return "PARTY" end
  return nil
end

-- -----------------------------
-- State
-- -----------------------------
local phase = "idle" -- "idle" | "active" | "ended"
local encounterID = 0
local encounterName = ""

local myName = ""
local myShort = ""
local myClass = ""
local myJumps = 0

local totals = {}      -- fullName -> jumps (ONLY jumpers)
local lastSeen = {}    -- fullName -> timestamp
local classByName = {} -- fullName -> classFile
local jumped = {}      -- fullName -> true once jumped

local lastBroadcastAt = 0
local lastHeartbeatAt = 0
local pendingBroadcast = false

-- winner arbitration / posting lock (SHORT names)
local claimWinner = nil
local postedBy = nil
local postTimer = nil

local lastJumpAt = 0

local function CancelPostTimer()
  if postTimer and postTimer.Cancel then postTimer:Cancel() end
  postTimer = nil
end

-- Throttle for hello/request spam
local throttle = { hello = 0, req = 0 }
local function Throttled(key, window)
  window = window or 1.0
  local t = Now()
  if throttle[key] and (t - throttle[key] < window) then return true end
  throttle[key] = t
  return false
end

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
    if type(count) == "number" and count > 0 then
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
      fs:SetText(string.format("%d. %s %d", i, ShortName(row.name), row.count))
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
  local ch = GetGroupChannel()
  if not ch then return end
  C_ChatInfo.SendAddonMessage(PREFIX, msg, ch)
end

local function SendHello()
  if phase == "idle" then return end
  if Throttled("hello", 2.0) then return end
  SendComm(string.format("HELLO:%d:%s", encounterID, myClass or ""))
end

local function SendRequest()
  if phase == "idle" then return end
  if Throttled("req", 1.5) then return end
  SendComm(string.format("REQ:%d", encounterID))
end

local function SendState()
  if phase == "idle" then return end
  if myJumps <= 0 then return end
  SendComm(string.format("S:%d:%d:%s", encounterID, myJumps, myClass or ""))
end

local function BroadcastUpdate(force)
  if phase ~= "active" then return end
  if myJumps <= 0 then return end

  local t = Now()
  if not force then
    if (t - lastBroadcastAt) < (db.broadcastInterval or DEFAULTS.broadcastInterval) then
      pendingBroadcast = true
      return
    end
  end

  pendingBroadcast = false
  lastBroadcastAt = t
  SendState()
end

local function Heartbeat()
  if phase ~= "active" then return end
  local t = Now()
  if (t - lastHeartbeatAt) < (db.heartbeatInterval or DEFAULTS.heartbeatInterval) then return end
  lastHeartbeatAt = t
  SendHello()
  SendState()
end

local function SendClaim(winnerShort, winnerCount)
  SendComm(string.format("C:%d:%s:%d", encounterID, winnerShort or "", tonumber(winnerCount or 0) or 0))
end

local function SendPosted(posterShort)
  SendComm(string.format("P:%d:%s", encounterID, posterShort or ""))
end

-- -----------------------------
-- Jump detection
-- -----------------------------
hooksecurefunc("JumpOrAscendStart", function()
  if phase ~= "active" then return end
  if UnitInVehicle("player") or UnitOnTaxi("player") then return end

  local t = Now()
  if (t - lastJumpAt) < 0.08 then return end
  lastJumpAt = t

  myJumps = myJumps + 1
  if myJumps == 1 then jumped[myName] = true end

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
    if type(count) == "number" and count > 0 then
      table.insert(arr, { name = name, count = count, short = ShortName(name) })
    end
  end
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.short < b.short
  end)
  return arr
end

local function DetermineWinnerShort()
  local arr = BuildSortedTotalsAll()
  if #arr == 0 then return nil, 0 end

  local maxCount = arr[1].count or 0
  local best = nil
  for _, row in ipairs(arr) do
    if row.count ~= maxCount then break end
    if not best or row.short < best then best = row.short end
  end
  return best, maxCount
end

local function JumpWord(n)
  return (n == 1) and "Jump!" or "Jumps!"
end

local function SanitizeForChat(s)
  if type(s) ~= "string" then return "" end
  return s:gsub("|", "||")
end

local function SafeSendChat(msg, chatType)
  msg = SanitizeForChat(msg)
  if msg == "" then return end

  -- Prefer the safe API (avoids your BreakTimerLite SendChatMessage hook/taint)
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    pcall(C_ChatInfo.SendChatMessage, msg, chatType)
    return
  end

  -- Fallback (still protected with pcall)
  pcall(SendChatMessage, msg, chatType)
end

local function BuildChatLines()
  local arr = BuildSortedTotalsAll()
  local boss = (encounterName ~= "" and encounterName) or "Boss"
  local total = #arr
  if total == 0 then return nil end

  local lines = {}
  table.insert(lines, string.format("Jump Leaderboard - %s", boss))

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
    local chunk = string.format("%d) %s - %d %s", i, row.short, row.count, JumpWord(row.count))
    if current == "" then
      current = chunk
    else
      local candidate = current .. " • " .. chunk
      if #candidate > 240 then
        flush()
        current = chunk
      else
        current = candidate
      end
    end
  end
  flush()

  table.insert(lines, "(Counts only players with JumpBoss who jumped at least once.)")
  return lines
end

local function PostToChat(lines)
  if not lines then return end
  local ch = GetGroupChannel()
  if not ch then return end
  for _, line in ipairs(lines) do
    SafeSendChat(line, ch)
  end
end

local function DeterministicDelaySeconds(nameShort)
  local sum = 0
  for i = 1, #nameShort do
    sum = (sum + string.byte(nameShort, i)) % 1000
  end
  return 0.35 + ((sum % 600) / 1000) -- 0.35 .. 0.95
end

local function HandleEncounterEndPosting()
  local window = db.syncWindow or DEFAULTS.syncWindow
  local postDelay = db.claimPostDelay or DEFAULTS.claimPostDelay

  CancelPostTimer()
  postedBy = nil
  claimWinner = nil

  C_Timer.After(window, function()
    if postedBy then return end

    local winnerShort, winnerCount = DetermineWinnerShort()
    if not winnerShort or winnerCount <= 0 then return end

    SendClaim(winnerShort, winnerCount)
    if winnerShort ~= myShort then return end

    local delay = postDelay + DeterministicDelaySeconds(myShort)
    postTimer = C_Timer.NewTimer(delay, function()
      postTimer = nil
      if postedBy then return end

      local finalWinner = select(1, DetermineWinnerShort())
      if finalWinner ~= myShort then return end

      postedBy = myShort
      SendPosted(myShort)
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
  wipe(jumped)

  lastBroadcastAt = 0
  lastHeartbeatAt = 0
  pendingBroadcast = false

  claimWinner = nil
  postedBy = nil
  CancelPostTimer()

  SendHello()
  SendRequest()
  UpdateUI()
end

local function FreezeEncounter(encIDFromEvent)
  phase = "ended"
  pendingBroadcast = false

  if encounterID == 0 or encounterID ~= encIDFromEvent then
    encounterID = encIDFromEvent or encounterID
    if encounterName == "" then encounterName = "Encounter" end
  end

  SendState()
  SendRequest()
  UpdateUI()
end

local function EndEncounterUI()
  phase = "idle"
  CancelPostTimer()
  UpdateUI()
end

-- -----------------------------
-- Incoming messages
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

  local tag, a, b, c = msg:match("^(%u+):([^:]*):?([^:]*):?(.*)$")
  if not tag then return end

  if tag == "HELLO" then
    local enc = tonumber(a) or 0
    local classFile = b or ""
    if phase == "idle" then return end
    if enc ~= encounterID then return end
    if classFile ~= "" then classByName[sender] = classFile end
    SendState()
    return
  end

  if tag == "REQ" then
    local enc = tonumber(a) or 0
    if phase == "idle" then return end
    if enc ~= encounterID then return end
    SendState()
    return
  end

  if tag == "S" then
    local enc = tonumber(a)
    local count = tonumber(b)
    local classFile = c or ""
    if not enc or count == nil then return end
    if phase == "idle" then return end
    if enc ~= encounterID then return end

    if count <= 0 and not jumped[sender] then
      if classFile ~= "" then classByName[sender] = classFile end
      return
    end

    if count > 0 then
      jumped[sender] = true
      totals[sender] = count
      lastSeen[sender] = Now()
      if classFile ~= "" then classByName[sender] = classFile end
      UpdateUI()
    end
    return
  end

  if tag == "C" then
    local enc = tonumber(a)
    local winnerShort = b
    local winnerCount = tonumber(c)
    if not enc or not winnerShort or winnerShort == "" or not winnerCount then return end
    if enc ~= encounterID then return end

    if not claimWinner or winnerShort < claimWinner then
      claimWinner = winnerShort
    end
    return
  end

  if tag == "P" then
    local enc = tonumber(a)
    local posterShort = b
    if not enc or not posterShort or posterShort == "" then return end
    if enc ~= encounterID then return end

    postedBy = posterShort
    CancelPostTimer()
    return
  end
end

-- -----------------------------
-- Slash commands
-- -----------------------------
local function SlashHelp()
  print("|cffffd100JumpBoss commands:|r")
  print("/jb show | hide")
  print("/jb lock | unlock")
  print("/jb scale <n>")
  print("/jb timeout <s>")
  print("/jb fade <s>")
  print("/jb top <n>  (min 5)")
end

SLASH_JUMPBOSS1 = "/jumpboss"
SLASH_JUMPBOSS2 = "/jb"
SlashCmdList.JUMPBOSS = function(msg)
  msg = (msg or "")
  local lower = msg:lower()

  if lower == "show" then db.show = true; ui:Show(); UpdateUI(); return end
  if lower == "hide" then db.show = false; ui:Hide(); return end
  if lower == "lock" then db.locked = true; print("JumpBoss: frame locked."); return end
  if lower == "unlock" then db.locked = false; print("JumpBoss: frame unlocked (drag to move)."); return end

  local cmd, val = lower:match("^(%S+)%s*(.*)$")
  if cmd == "scale" and val ~= "" then
    local n = tonumber(val)
    if n and n > 0.2 and n < 3.0 then db.scale = n; ApplyUISettings(); return end
  elseif cmd == "timeout" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 0.5 and n <= 300 then db.staleTimeout = n; return end
  elseif cmd == "fade" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 0.2 and n <= 60 then db.fadeDuration = n; return end
  elseif cmd == "top" and val ~= "" then
    local n = tonumber(val)
    if n and n >= 5 and n <= 50 then db.postTopN = math.floor(n); return end
  end

  SlashHelp()
end

-- -----------------------------
-- Events
-- -----------------------------
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end

    myName = PlayerFullName()
    myShort = ShortName(myName)
    local _, classFile = UnitClass("player")
    myClass = classFile or ""

    JumpBossDB = JumpBossDB or {}
    db = JumpBossDB
    CopyDefaults(db, DEFAULTS)

    if type(db.postTopN) == "number" and db.postTopN < 5 then
      db.postTopN = 5
    end

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

  if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
    if phase ~= "idle" then
      SendHello()
      SendRequest()
    end
    return
  end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
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
