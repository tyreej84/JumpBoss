local Harness = {}
Harness.__index = Harness

local SEND_ADDON_RESULT = {
  Success = 0,
  InvalidPrefix = 1,
  InvalidMessage = 2,
  AddonMessageThrottle = 3,
  InvalidChatType = 4,
  NotInGroup = 5,
  TargetRequired = 6,
  InvalidChannel = 7,
  ChannelThrottle = 8,
  GeneralError = 9,
  NotInGuild = 10,
  AddOnMessageLockdown = 11,
  TargetOffline = 12,
}

local function stripRealm(fullName)
  return (fullName or ""):match("^[^-]+") or (fullName or "")
end

local function clearTable(tbl)
  for key in pairs(tbl) do
    tbl[key] = nil
  end
end

local function defaultClassColors()
  return {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PRIEST = { r = 1.0, g = 1.0, b = 1.0 },
    DRUID = { r = 1.0, g = 0.49, b = 0.04 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE = { r = 1.0, g = 0.96, b = 0.41 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    SHAMAN = { r = 0.0, g = 0.44, b = 0.87 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    MONK = { r = 0.0, g = 1.0, b = 0.59 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    EVOKER = { r = 0.2, g = 0.58, b = 0.5 },
  }
end

local function timerLess(a, b)
  if a.when == b.when then
    return a.id < b.id
  end
  return a.when < b.when
end

function Harness.new(options)
  local self = setmetatable({}, Harness)
  self.addonPath = assert(options and options.addonPath, "addonPath is required")
  self.time = 0
  self.nextTimerId = 0
  self.timers = {}
  self.clients = {}
  self.groupMode = (options and options.groupMode) or "RAID"
  self.throttleMax = (options and options.throttleMax) or 10
  self.throttleRefill = (options and options.throttleRefill) or 1
  self.deliveryLatency = (options and options.deliveryLatency) or 0.02
  self.lockAddonMessagesInCombat = (options and options.lockAddonMessagesInCombat) or false
  self.classColors = defaultClassColors()
  return self
end

function Harness:schedule(delay, callback)
  self.nextTimerId = self.nextTimerId + 1
  local timer = {
    id = self.nextTimerId,
    when = self.time + math.max(0, delay or 0),
    callback = callback,
    canceled = false,
  }

  function timer:Cancel()
    self.canceled = true
  end

  table.insert(self.timers, timer)
  table.sort(self.timers, timerLess)
  return timer
end

function Harness:runDueTimers()
  while true do
    local timer = self.timers[1]
    if not timer or timer.when > self.time then
      return
    end

    table.remove(self.timers, 1)
    if not timer.canceled then
      timer.callback()
    end
  end
end

function Harness:tick(step)
  self.time = self.time + step
  self:runDueTimers()

  for _, client in ipairs(self.clients) do
    for _, frame in ipairs(client.frames) do
      local onUpdate = frame.scripts.OnUpdate
      if onUpdate then
        onUpdate(frame, step)
      end
    end
  end

  self:runDueTimers()
end

function Harness:advance(seconds, step)
  local increment = step or 0.05
  local remaining = seconds
  while remaining > 0 do
    local delta = math.min(increment, remaining)
    self:tick(delta)
    remaining = remaining - delta
  end
end

function Harness:isClientGrouped(client, chatType)
  if chatType == "RAID" then
    return self.groupMode == "RAID"
  end
  if chatType == "INSTANCE_CHAT" then
    return self.groupMode == "INSTANCE_CHAT"
  end
  if chatType == "PARTY" then
    return self.groupMode == "PARTY" or self.groupMode == "INSTANCE_CHAT" or self.groupMode == "RAID"
  end
  return false
end

function Harness:updateThrottle(client, prefix)
  client.throttle[prefix] = client.throttle[prefix] or {
    allowance = self.throttleMax,
    last = self.time,
  }

  local bucket = client.throttle[prefix]
  local elapsed = math.max(0, self.time - bucket.last)
  bucket.allowance = math.min(self.throttleMax, bucket.allowance + (elapsed * self.throttleRefill))
  bucket.last = self.time
  return bucket
end

function Harness:deliverAddonMessage(senderClient, prefix, message, chatType)
  local senderFullName = senderClient.fullName

  for _, client in ipairs(self.clients) do
    if client ~= senderClient and client.prefixes[prefix] and self:isClientGrouped(client, chatType) then
      local recipient = client
      self:schedule(self.deliveryLatency, function()
        recipient:fireEvent("CHAT_MSG_ADDON", prefix, message, chatType, senderFullName)
      end)
    end
  end
end

function Harness:sendAddonMessage(client, prefix, message, chatType)
  if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
    return SEND_ADDON_RESULT.InvalidPrefix
  end
  if type(message) ~= "string" or message == "" or #message > 255 then
    return SEND_ADDON_RESULT.InvalidMessage
  end
  if not self:isClientGrouped(client, chatType) then
    return SEND_ADDON_RESULT.NotInGroup
  end
  if self.lockAddonMessagesInCombat and client.inCombat then
    return SEND_ADDON_RESULT.AddOnMessageLockdown
  end

  local bucket = self:updateThrottle(client, prefix)
  if bucket.allowance < 1 then
    return SEND_ADDON_RESULT.AddonMessageThrottle
  end

  bucket.allowance = bucket.allowance - 1
  table.insert(client.addonSends, {
    at = self.time,
    prefix = prefix,
    message = message,
    chatType = chatType,
  })
  self:deliverAddonMessage(client, prefix, message, chatType)
  return SEND_ADDON_RESULT.Success
end

function Harness:sendChatMessage(client, message, chatType)
  client.chatAttempts = (client.chatAttempts or 0) + 1
  if client.inCombat or (client.chatRestrictionState or 0) ~= 0 then
    error("SendChatMessage is blocked by combat or chat restriction")
  end
  if client.blockNextChat then
    client.blockNextChat = false
    client:fireEvent("ADDON_ACTION_BLOCKED", "JumpBoss", "UNKNOWN()")
    return
  end

  table.insert(client.chatLog, {
    at = self.time,
    chatType = chatType or "SAY",
    message = message,
  })
end

function Harness:createFontString(parent)
  local fs = {
    parent = parent,
    text = "",
    alpha = 1,
    shown = true,
    color = { 1, 1, 1, 1 },
    point = { "TOPLEFT", nil, "TOPLEFT", 0, 0 },
  }

  function fs:ClearAllPoints()
    self.point = nil
  end

  function fs:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "number" then
      self.point = { point, nil, point, relativeTo or 0, relativePoint or 0 }
      return
    end

    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
  end

  function fs:SetText(text)
    self.text = text or ""
  end

  function fs:GetText()
    return self.text
  end

  function fs:SetAlpha(alpha)
    self.alpha = alpha
  end

  function fs:SetTextColor(r, g, b, a)
    self.color = { r, g, b, a }
  end

  function fs:Show()
    self.shown = true
  end

  function fs:Hide()
    self.shown = false
  end

  return fs
end

function Harness:createFrame(client, frameType, name, parent, template)
  local frame = {
    client = client,
    frameType = frameType,
    name = name,
    parent = parent,
    template = template,
    events = {},
    scripts = {},
    point = { "CENTER", parent, "CENTER", 0, 0 },
    shown = true,
    width = 0,
    height = 0,
    scale = 1,
  }

  function frame:SetClampedToScreen() end
  function frame:SetMovable() end
  function frame:EnableMouse() end
  function frame:RegisterForDrag() end
  function frame:SetBackdrop() end
  function frame:SetBackdropColor() end
  function frame:StartMoving() end
  function frame:StopMovingOrSizing() end
  function frame:SetSize(width, height)
    self.width = width
    self.height = height
  end
  function frame:SetScale(scale)
    self.scale = scale
  end
  function frame:ClearAllPoints()
    self.point = nil
  end
  function frame:SetPoint(point, relativeTo, relativePoint, x, y)
    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
  end
  function frame:GetPoint()
    local p = self.point or { "CENTER", nil, "CENTER", 0, 0 }
    return p[1], p[2], p[3], p[4], p[5]
  end
  function frame:SetShown(value)
    self.shown = not not value
  end
  function frame:Show()
    self.shown = true
  end
  function frame:Hide()
    self.shown = false
  end
  function frame:RegisterEvent(event)
    self.events[event] = true
  end
  function frame:UnregisterEvent(event)
    self.events[event] = nil
  end
  function frame:SetScript(name, func)
    self.scripts[name] = func
  end
  function frame:CreateFontString()
    return client.harness:createFontString(self)
  end

  table.insert(client.frames, frame)
  if name then
    client.env[name] = frame
  end
  return frame
end

function Harness:buildEnvironment(client)
  local env = {}
  local hooks = {}
  local uiParent = { name = "UIParent" }

  local function hooksecurefunc(name, callback)
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], callback)
  end

  local function invokeHook(name, ...)
    local list = hooks[name]
    if not list then return end
    for _, callback in ipairs(list) do
      callback(...)
    end
  end

  local cTimer = {}
  function cTimer.After(delay, callback)
    client.harness:schedule(delay, callback)
  end
  function cTimer.NewTimer(delay, callback)
    return client.harness:schedule(delay, callback)
  end

  local chatInfo = {}
  function chatInfo.RegisterAddonMessagePrefix(prefix)
    if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then
      return 2
    end
    client.prefixes[prefix] = true
    return 0
  end
  function chatInfo.SendAddonMessage(prefix, message, chatType)
    return client.harness:sendAddonMessage(client, prefix, message, chatType or "PARTY")
  end
  function chatInfo.SendChatMessage(message, chatType)
    return client.harness:sendChatMessage(client, message, chatType)
  end

  local function SendAddonMessage(prefix, message, chatType)
    local result = client.harness:sendAddonMessage(client, prefix, message, chatType or "PARTY")
    return result == SEND_ADDON_RESULT.Success
  end

  local function SendChatMessage(message, chatType)
    return client.harness:sendChatMessage(client, message, chatType)
  end

  local function UnitName(unit)
    if unit == "player" then
      return client.name, client.realm
    end
    return nil
  end

  local function UnitClass(unit)
    if unit == "player" then
      return client.classFile, client.classFile
    end
    return nil
  end

  local function CreateFrame(frameType, name, parent, template)
    return client.harness:createFrame(client, frameType, name, parent, template)
  end

  local function Ambiguate(fullName, style)
    if style == "short" then
      return stripRealm(fullName)
    end
    return fullName
  end

  local function IsInRaid()
    return client.harness.groupMode == "RAID"
  end

  local function IsInGroup(category)
    if category == env.LE_PARTY_CATEGORY_INSTANCE then
      return client.harness.groupMode == "INSTANCE_CHAT"
    end
    return client.harness.groupMode == "PARTY" or client.harness.groupMode == "RAID" or client.harness.groupMode == "INSTANCE_CHAT"
  end

  local function JumpOrAscendStart()
    invokeHook("JumpOrAscendStart")
  end

  env._G = env
  env.assert = assert
  env.error = error
  env.ipairs = ipairs
  env.next = next
  env.pairs = pairs
  env.pcall = pcall
  env.select = select
  env.tonumber = tonumber
  env.tostring = tostring
  env.type = type
  env.unpack = table.unpack or unpack
  env.math = math
  env.string = string
  env.table = table
  env.os = os
  env.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(index, ...))
    end
    table.insert(client.printLog, table.concat(parts, " "))
  end

  env.GetTime = function()
    return client.harness.time
  end
  env.GetRealmName = function()
    return client.realm
  end
  env.UnitName = UnitName
  env.UnitClass = UnitClass
  env.Ambiguate = Ambiguate
  env.IsInRaid = IsInRaid
  env.IsInGroup = IsInGroup
  env.UnitInVehicle = function() return false end
  env.UnitOnTaxi = function() return false end
  env.UnitAffectingCombat = function(unit)
    return unit == "player" and client.inCombat or false
  end
  env.InCombatLockdown = function()
    return client.inCombat
  end
  env.securecallfunction = function(func, ...)
    return func(...)
  end
  env.issecurevariable = function()
    return true
  end
  env.wipe = clearTable
  env.CreateFrame = CreateFrame
  env.C_Timer = cTimer
  env.C_ChatInfo = chatInfo
  env.C_RestrictedActions = {
    GetAddOnRestrictionState = function() return client.chatRestrictionState or 0 end,
  }
  env.Enum = env.Enum or {}
  env.Enum.AddOnRestrictionType = { Chat = 5 }
  env.Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
  env.RegisterAddonMessagePrefix = chatInfo.RegisterAddonMessagePrefix
  env.SendAddonMessage = SendAddonMessage
  env.SendChatMessage = SendChatMessage
  env.hooksecurefunc = hooksecurefunc
  env.JumpOrAscendStart = JumpOrAscendStart
  env.UIParent = uiParent
  env.LE_PARTY_CATEGORY_INSTANCE = 1
  env.BackdropTemplate = {}
  env.RAID_CLASS_COLORS = client.harness.classColors
  env.SlashCmdList = {}
  env.JumpBossDB = {}

  return env
end

function Harness:createClient(options)
  local client = {
    harness = self,
    name = assert(options.name, "client name is required"),
    realm = options.realm or "TestRealm",
    classFile = options.classFile or "MAGE",
    inCombat = false,
    frames = {},
    prefixes = {},
    addonSends = {},
    chatLog = {},
    printLog = {},
    throttle = {},
  }

  client.fullName = client.name .. "-" .. client.realm
  client.env = self:buildEnvironment(client)

  function client:loadAddon()
    local chunk, err
    if _VERSION == "Lua 5.1" and setfenv then
      chunk, err = loadfile(self.harness.addonPath)
      if not chunk then error(err) end
      setfenv(chunk, self.env)
    else
      chunk, err = loadfile(self.harness.addonPath, "t", self.env)
      if not chunk then error(err) end
    end

    chunk("JumpBoss")
    self:fireEvent("ADDON_LOADED", "JumpBoss")
  end

  function client:fireEvent(event, ...)
    for _, frame in ipairs(self.frames) do
      if frame.events[event] and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame, event, ...)
      end
    end
  end

  function client:getFrame(name)
    return self.env[name]
  end

  function client:getVisibleLines()
    local frame = self:getFrame("JumpBossFrame")
    if not frame or not frame.lines then
      return {}
    end

    local lines = {}
    for _, fontString in ipairs(frame.lines) do
      if fontString.shown and fontString.text ~= "" then
        lines[#lines + 1] = fontString.text
      end
    end
    return lines
  end

  table.insert(self.clients, client)
  return client
end

function Harness:broadcastEvent(event, ...)
  for _, client in ipairs(self.clients) do
    client:fireEvent(event, ...)
  end
end

function Harness:setCombat(client, inCombat)
  client.inCombat = not not inCombat
  if not client.inCombat then
    client:fireEvent("PLAYER_REGEN_ENABLED")
  end
end

return Harness
