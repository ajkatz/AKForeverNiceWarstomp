-- Stand-in for the WoW client, enough to run AKForeverNiceWarstomp under a plain Lua interpreter. Same design
-- as the other addons' mocks. What it models of Blizzard's side:
--
--  * units: the player, a group, a target and nameplates, each with a race, a side and debuffs;
--  * unit events delivered per frame (RegisterUnitEvent), with payloads that can be made secret - other
--    people's casts arrive with the spell hidden, as on the real client;
--  * chat: C_ChatInfo.SendChatMessage goes out only inside a key press (Mock.key, Mock.slash); outside
--    one the client answers with ADDON_ACTION_BLOCKED, as the Forever realms do;
--  * the keyboard: a frame with the keyboard enabled hears every key; one that does not pass keys on
--    SWALLOWS them, which the tests count (it must never happen);
--  * events, one-shot timers, the slash command table, saved variables, the clock, secret values.
--
-- The addon's files run in an environment with the game's Lua 5.1 table library (no table.unpack, a
-- global unpack), so that a 5.4-only call fails here before it fails in the game.
-- Not loaded by the game (not in the .toc).
local Mock = {}

local REAL_PRINT = print
local ADDON = "AKForeverNiceWarstomp"
local FILES = { "Core.lua", "Stomp.lua", "Call.lua", "Diagnostics.lua" }

Mock.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })
Mock.STOMP, Mock.BOLT = 20549, 403
Mock.STOMP2 = 99999 -- the same stomp under another number

local function isSecret(value)
    return value == Mock.SECRET
end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local methods = {}
local newWidget

function methods.GetObjectType(self) return self.__kind end
function methods.SetSize(self, w, h) self.__width, self.__height = w, h end
function methods.SetPoint(self, ...) self.__points[#self.__points + 1] = { ... } end
function methods.Show(self) self.__shown = true end
function methods.Hide(self) self.__shown = false end
function methods.IsShown(self) return self.__shown end
function methods.SetAlpha(self, a) self.__alpha = a end
function methods.SetScale(self, s) self.__scale = s end
function methods.GetScale(self) return self.__scale or 1 end
function methods.SetFrameStrata(self, s) self.__strata = s end
function methods.GetName(self) return self.__name end
function methods.SetScript(self, name, fn) self.__scripts[name] = fn end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.SetText(self, t) self.__text = t end
function methods.GetText(self) return self.__text end
function methods.SetTextColor(self, r, g, b) self.__colour = { r, g, b } end
-- Events that are not for addons (the combat log's): registering for one does not raise an error - it
-- is a FORBIDDEN action, and the client puts up its "has been blocked" popup. The tests count them.
local FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT = true, COMBAT_LOG_EVENT_UNFILTERED = true }

local function mayRegister(event)
    if Mock.state.unknownEvents[event] then
        error("unknown event " .. event)
    end
    if FORBIDDEN_EVENTS[event] then
        Mock.forbidden = Mock.forbidden + 1
        Mock.fire("ADDON_ACTION_FORBIDDEN", ADDON, "UNKNOWN()")
        return false
    end
    return true
end

function methods.RegisterEvent(self, event)
    if mayRegister(event) then
        self.__events[event] = true
    end
end
function methods.RegisterUnitEvent(self, event, unit)
    if mayRegister(event) then
        self.__unitEvents[event] = unit
    end
end
function methods.CreateFontString(self, name, layer, font)
    local fs = newWidget("FontString", name, self)
    fs.__font = font
    return fs
end
function methods.CreateAnimationGroup(self)
    local group = { __scripts = {}, __playing = false }
    function group:CreateAnimation(kind)
        local animation = { kind = kind }
        function animation:SetFromAlpha(a) self.from = a end
        function animation:SetToAlpha(a) self.to = a end
        function animation:SetStartDelay(d) self.delay = d end
        function animation:SetDuration(d) self.duration = d end
        group.__animation = animation
        return animation
    end
    function group:SetScript(name, fn) self.__scripts[name] = fn end
    function group:Play() self.__playing = true end
    function group:Stop() self.__playing = false end
    self.__fade = group
    return group
end
-- the keyboard: passing keys on can only be set out of combat (as on the client), and a client can be
-- told not to confirm it
function methods.SetPropagateKeyboardInput(self, propagate)
    if Mock.state.combat then
        error("SetPropagateKeyboardInput: not in combat")
    end
    if not Mock.state.propagateIgnored then
        self.__propagate = propagate
    end
end
function methods.GetPropagateKeyboardInput(self) return self.__propagate == true end
function methods.EnableKeyboard(self, enable) self.__keyboard = enable end

function newWidget(kind, name, parent)
    local w = setmetatable({
        __kind = kind, __name = name, __parent = parent, __points = {}, __scripts = {}, __events = {}, __unitEvents = {},
        __shown = true,
    }, { __index = methods })
    if name then
        _G[name] = w
        Mock.named[name] = true
    end
    Mock.frames[#Mock.frames + 1] = w
    return w
end

------------------------------------------------------------------------
-- Install: a fresh client
------------------------------------------------------------------------
function Mock.install(options)
    options = options or {}
    for name in pairs(Mock.named or {}) do
        _G[name] = nil -- the last client's frames go with it
    end
    Mock.named = {}
    Mock.frames, Mock.printed, Mock.timers, Mock.errors = {}, {}, {}, {}
    Mock.said, Mock.sounds, Mock.swallowed, Mock.forbidden = {}, {}, 0, 0
    Mock.state = {
        now = 1000, combat = options.combat or false, hardware = false, unknownEvents = {},
        chatBlockedEvenInKeyPress = options.chatBlockedEvenInKeyPress or false,
        propagateIgnored = options.propagateIgnored or false,
        keyUpBlocked = options.keyUpBlocked or false,
        noKeyUps = options.noKeyUps or false, -- this client: the frame is never told that a key came up
        aurasSecret = false,
        units = {
            player = { name = "Purrdee Bubson", race = "Tauren", player = true, guid = "Player-1" },
        },
    }
    local state = Mock.state
    for _, event in ipairs(options.unknownEvents or {}) do
        state.unknownEvents[event] = true
    end

    for name in pairs(Mock.globals or {}) do
        _G[name] = nil
    end
    local G = {}
    local function global(name, value)
        G[name] = value
        _G[name] = value
    end
    Mock.globals = G

    global("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end)
    global("issecretvalue", isSecret)
    global("GetTime", function() return state.now end)
    global("date", function() return "2026-10-01 12:34:56" end)
    global("InCombatLockdown", function() return state.combat end)
    global("geterrorhandler", function() return function(err) Mock.errors[#Mock.errors + 1] = err end end)
    global("C_AddOns", { GetAddOnMetadata = function() return options.version or "0.1.0-test" end })
    global("GetBuildInfo", function() return "1.60.1", "70170", "Oct  1 2026", 16001 end)
    global("SlashCmdList", {})
    global("CreateFrame", function(kind, name, parent)
        return newWidget(kind, name, parent)
    end)
    global("C_Timer", { After = function(seconds, fn)
        Mock.timers[#Mock.timers + 1] = { at = state.now + seconds, fn = fn }
    end })
    global("UIParent", newWidget("Frame", "UIParent"))
    global("PlaySound", function(id, channel) Mock.sounds[#Mock.sounds + 1] = id end)

    -- units
    local function unit(token) return state.units[token] end
    global("UnitExists", function(token) return unit(token) ~= nil end)
    global("UnitIsPlayer", function(token) return unit(token) and unit(token).player == true or false end)
    global("UnitRace", function(token)
        local u = unit(token)
        if not u then return nil end
        if u.raceSecret then return Mock.SECRET, Mock.SECRET end
        return u.race, u.race
    end)
    global("UnitCanAttack", function(_, token) return unit(token) and unit(token).hostile == true or false end)
    global("UnitGUID", function(token) return unit(token) and unit(token).guid or nil end)
    global("GetUnitName", function(token) return unit(token) and unit(token).name or nil end)
    global("UnitIsUnit", function(a, b)
        if (unit(a) and unit(a).compareSecret) or (unit(b) and unit(b).compareSecret) then
            return Mock.SECRET
        end
        return unit(a) ~= nil and unit(b) ~= nil and unit(a).guid == unit(b).guid
    end)
    global("IsInRaid", function() return state.raid == true end)

    global("Enum", {
        SpellDiminishCategory = { Root = 0, Taunt = 1, Stun = 2 },
        SpellDiminishRuleset = { None = 0, PvE = 1, PvP = 2 },
    })
    global("C_Spell", { GetSpellName = function(id)
        return ({ [Mock.STOMP] = "War Stomp", [Mock.BOLT] = "Lightning Bolt", [Mock.STOMP2] = "War Stomp" })[id]
    end })
    global("C_SpellBook", { IsSpellKnown = function(id) return id == Mock.STOMP end })
    global("C_Secrets", {
        GetSpellCastSecrecy = function() return 2 end,
        GetSpellAuraSecrecy = function() return 2 end,
        ShouldSpellAuraBeSecret = function() return state.aurasSecret end,
        ShouldAurasBeSecret = function() return state.aurasSecret end,
    })
    global("C_SpellDiminish", {
        IsSystemSupported = function() return options.stunTracker ~= false end,
        ShouldTrackSpellDiminishCategory = function() return true end,
    })
    global("C_CombatLog", { IsCombatLogRestricted = function() return true end })
    global("C_UnitAuras", { GetAuraDataBySpellName = function(token, name)
        local u = unit(token)
        if not u or not u.debuffs or not u.debuffs[name] or u.debuffs[name] < state.now then
            return nil
        end
        if state.aurasSecret then
            return Mock.SECRET
        end
        return { name = name, spellId = Mock.STOMP }
    end })

    -- chat: only inside a key press
    global("C_ChatInfo", {
        AreOutgoingAddonChatMessagesRestricted = function() return true end,
        SendChatMessage = function(text, kind)
            if not state.hardware or state.chatBlockedEvenInKeyPress then
                Mock.fire("ADDON_ACTION_BLOCKED", ADDON, "UNKNOWN()")
                return
            end
            Mock.said[#Mock.said + 1] = { text = text, kind = kind, at = state.now }
            Mock.fire("CHAT_MSG_YELL", text, state.units.player.name)
        end,
    })

    if options.db then
        global("AKForeverNiceWarstompDB", options.db)
    else
        global("AKForeverNiceWarstompDB", nil)
    end

    -- the addon's files, in the TOC's order, in a 5.1-shaped environment
    local ns = {}
    local root = options.root or "."
    local gameTable = {}
    for key, value in pairs(table) do
        gameTable[key] = value
    end
    gameTable.unpack, gameTable.pack = nil, nil
    local gameEnv = setmetatable({ table = gameTable, unpack = table.unpack }, {
        __index = _G,
        __newindex = function(_, key, value)
            _G[key] = value
        end,
    })
    for _, file in ipairs(FILES) do
        local chunk, err = loadfile(root .. "/" .. file, "t", gameEnv)
        if not chunk then
            error(err)
        end
        chunk(ADDON, ns)
    end
    Mock.ns = ns
    return ns, state
end

------------------------------------------------------------------------
-- Events and time
------------------------------------------------------------------------
function Mock.fire(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

-- a unit event: to the frames that asked for this event of this unit
function Mock.unitEvent(unit, event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__unitEvents[event] == unit and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function Mock.login()
    Mock.fire("ADDON_LOADED", ADDON)
    Mock.fire("PLAYER_LOGIN")
end

function Mock.advance(seconds)
    local state = Mock.state
    local target = state.now + seconds
    while true do
        local nextIndex, nextAt
        for index, timer in ipairs(Mock.timers) do
            if timer.at <= target and (not nextAt or timer.at < nextAt) then
                nextIndex, nextAt = index, timer.at
            end
        end
        if not nextIndex then
            break
        end
        local timer = table.remove(Mock.timers, nextIndex)
        state.now = math.max(state.now, timer.at)
        timer.fn()
    end
    state.now = target
end

------------------------------------------------------------------------
-- The world
------------------------------------------------------------------------
-- a unit under a token: Mock.unit("party1", { name = "Holly Boy", race = "Tauren", player = true })
function Mock.unit(token, info)
    if info then
        info.guid = info.guid or ("Guid-" .. tostring(info.name or token))
    end
    Mock.state.units[token] = info
    return info
end

-- an enemy with a nameplate
function Mock.plate(index, info)
    local token = "nameplate" .. index
    info = info or {}
    info.name, info.hostile = info.name or ("Kobold " .. index), info.hostile ~= false
    Mock.unit(token, info)
    Mock.fire("NAME_PLATE_UNIT_ADDED", token)
    return token
end

function Mock.plateGone(index)
    local token = "nameplate" .. index
    Mock.fire("NAME_PLATE_UNIT_REMOVED", token)
    Mock.state.units[token] = nil
end

-- a cast: START, the time it takes, SUCCEEDED. Somebody else's arrives with the spell hidden unless
-- `named` is given.
function Mock.cast(unit, spellID, seconds, named)
    local shown = (unit == "player" or named) and spellID or Mock.SECRET
    Mock.unitEvent(unit, "UNIT_SPELLCAST_START", unit, "Cast-1", shown)
    Mock.advance(seconds or 0.5)
    Mock.unitEvent(unit, "UNIT_SPELLCAST_SUCCEEDED", unit, "Cast-1", shown)
end

-- a mob stunned by a stomp: its auras change (payload secret in combat), and - as asked - the client's
-- stun tracker reports it, and the debuff is there to read
function Mock.stunned(token, how)
    how = how or {}
    local u = Mock.state.units[token]
    if u and how.debuff ~= false then
        u.debuffs = u.debuffs or {}
        u.debuffs["War Stomp"] = Mock.state.now + 2 -- (the stun lasts two seconds)
    end
    Mock.unitEvent(token, "UNIT_AURA", token, Mock.state.aurasSecret and Mock.SECRET or { addedAuras = {} })
    if how.tracker then
        Mock.unitEvent(token, "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED", token,
            how.tracker == "secret" and Mock.SECRET or { category = 2, startTime = Mock.state.now, duration = 2, isImmune = how.tracker == "immune" })
    end
end

-- your stomp, landing on these nameplates
function Mock.stomp(plates, how)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.5)
    for _, index in ipairs(plates or {}) do
        Mock.stunned("nameplate" .. index, how)
    end
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
end

------------------------------------------------------------------------
-- The keyboard
------------------------------------------------------------------------
-- a key goes down: every frame with the keyboard enabled hears it; one that does not pass it on swallows
-- it. A fresh press is a key press to the client (hardware); a repeat of a held key is not.
function Mock.keyDown(key, repeated)
    local state = Mock.state
    state.hardware = not repeated
    for _, frame in ipairs(Mock.frames) do
        if frame.__keyboard then
            if frame.__scripts.OnKeyDown then
                frame.__scripts.OnKeyDown(frame, key or "W")
            end
            if not frame.__propagate then
                Mock.swallowed = Mock.swallowed + 1
            end
        end
    end
    state.hardware = false
end

-- a key comes up: a key event to the client, unless this client is one that does not count releases
function Mock.keyUp(key)
    local state = Mock.state
    if state.holding == (key or "W") then
        state.holding = nil
    end
    if state.noKeyUps then
        return
    end
    state.hardware = not state.keyUpBlocked
    for _, frame in ipairs(Mock.frames) do
        if frame.__keyboard and frame.__scripts.OnKeyUp then
            frame.__scripts.OnKeyUp(frame, key or "W")
        end
    end
    state.hardware = false
end

-- a tap: down and up
function Mock.key(key)
    Mock.keyDown(key)
    Mock.keyUp(key)
end

-- a key held: it went down once, and repeats
function Mock.keyRepeat(key)
    Mock.keyDown(key, true)
end

-- a key held for a while: the keyboard repeats it - the first time after its repeat delay, half a second,
-- then thirty times a second - and time passes
function Mock.hold(key, seconds)
    local state = Mock.state
    local held, gap = 0, (state.holding == key) and 0.033 or 0.5
    while held + gap <= seconds do
        Mock.advance(gap)
        held = held + gap
        Mock.keyDown(key, true)
        state.holding = key
        gap = 0.033
    end
    Mock.advance(seconds - held)
end

-- a slash command is typed and sent with Enter: a key press
function Mock.slash(text)
    local state = Mock.state
    state.hardware = true
    SlashCmdList.AKFOREVERNICEWARSTOMP(text)
    state.hardware = false
end

Mock.realPrint = REAL_PRINT

return Mock
