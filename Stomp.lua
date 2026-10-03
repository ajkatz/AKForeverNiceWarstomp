-- Stomp: seeing a War Stomp, and counting what it hit.
--
-- WHAT THE CLIENT SHOWS AN ADDON. Your own casts come with the spell's name on them. Somebody else's
-- do not: for every unit but you the cast events arrive with the spell hidden (a secret value), unless
-- the spell is flagged as never secret - '/ws diag' says which War Stomp is. And the debuffs on a mob
-- are hidden while you are in combat yourself. So:
--   * YOUR stomp is known for sure: UNIT_SPELLCAST_SUCCEEDED on "player", spell 20549;
--   * ANOTHER Tauren's is known for sure when the client names the spell, and guessed otherwise: a
--     cast that took half a second, by a Tauren, that stunned something. ('/ws others sure' turns the
--     guessing off.) Only units the client hands us can be watched at all: your group, your target,
--     your focus, and everybody with a nameplate - for the Taurens around you, friendly nameplates.
--
-- COUNTING THE HITS. A stomp stuns up to five enemies in the same instant. Every enemy nameplate has
-- its own event frame, and three things are noted on it with the time: its auras changed (the event
-- alone, never its payload - that may be secret), the client's own diminishing-returns tracker
-- reported a stun on it, and - when the client lets us read it - the War Stomp debuff itself. Half a
-- second after the cast the count is taken from the best of the three that has anything to say.
--
-- Every stomp is kept with all three counts (db.stomps), so that the report shows which one tells the
-- truth on this client.
--
-- A CAST CUT SHORT. A stun ends a cast. What a mob casts is hidden from us, but THAT it was casting and
-- that the cast was interrupted is not: its frame hears UNIT_SPELLCAST_START and
-- UNIT_SPELLCAST_INTERRUPTED (a channel: CHANNEL_START and CHANNEL_STOP). A mob whose cast was cut in
-- the stomp's own instant was cut by the stomp - counted with each stomp (`interrupted`,
-- `channelsStopped`), and where the client names who did the interrupting, checked against the stomper.
-- Should the client only say "stopped" for a stunned caster, a cast that stopped in that instant without
-- having succeeded counts the same (`stoppedShort`). Written down with the stomp (`cut`); the call is the same.
local _, ns = ...

local Stomp = {}
ns.Stomp = Stomp

local STOMP_ID = 20549
local WINDOW_BEFORE = 0.2       -- the stuns land with the cast: a mob's change counts from this long before
local WINDOW_AFTER = 0.45       -- ... to this long after the cast's own event
local DECIDE_AFTER = 0.6        -- when the count is taken
local CAST_MIN, CAST_MAX = 0.3, 0.85 -- "a half-second cast", as its two events arrive
local SAME_CASTER = 1.5         -- one stomp seen through two unit tokens is one stomp
local AURA_TIMES = 6            -- aura changes remembered per mob
local STOMPS_KEPT = 40
local OWN_CASTS_KEPT = 15       -- your own last casts, by number and name, for the report

local UNIT_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA", "UNIT_COMBAT",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}
local STUN_EVENT = "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED" -- only where the client says it runs the tracker

local frames = {}   -- [unit token] = its event frame
local plates = {}   -- [nameplate token] = true while the plate is up
local recent = {}   -- [caster] = when their last stomp was taken up
local stompName = "War Stomp"
Stomp.seen = { casts = 0, named = 0, hidden = 0, own = 0, guessed = 0, decided = 0, auraChanges = 0, nameplates = 0 }
Stomp.ownCasts = {}
Stomp.otherCasts = {} -- other PLAYERS' casts, as far as the client lets us see them: for the report

-- a unit function's first result - or nil when the call fails or the answer is secret
local function fact(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok or ns.IsSecret(value) then
        return nil
    end
    return value
end

local function spellName(spellID)
    return fact(C_Spell and C_Spell.GetSpellName, spellID)
end

-- "War Stomp" under whatever number the client casts it, and however it spells it
local function isStomp(spellID)
    if spellID == STOMP_ID then
        return true
    end
    local name = spellName(spellID)
    if type(name) ~= "string" then
        return false
    end
    return name == stompName or string.find(string.gsub(string.lower(name), "%s+", ""), "warstomp", 1, true) ~= nil
end

local function stunCategory()
    return Enum and Enum.SpellDiminishCategory and Enum.SpellDiminishCategory.Stun
end

------------------------------------------------------------------------
-- One event frame per unit: the frame knows whose events it hears, whatever the payload hides
------------------------------------------------------------------------
local function forget(frame)
    frame.castStart, frame.stunAt, frame.stunImmune, frame.combat, frame.combatAt = nil, nil, nil, nil, nil
    frame.auras = {}
    frame.casting, frame.channelling, frame.cutAt, frame.cutBy, frame.channelCutAt = nil, nil, nil, nil, nil
    frame.stopAt, frame.succeededAt = nil, nil
end

local function onUnitEvent(frame, event, _, first, second, third)
    local now = GetTime()
    if event == "UNIT_AURA" then
        Stomp.seen.auraChanges = Stomp.seen.auraChanges + 1
        local times = frame.auras
        times[#times + 1] = now
        if #times > AURA_TIMES then
            table.remove(times, 1)
        end
    elseif event == "UNIT_SPELLCAST_START" then
        frame.castStart = now
        frame.casting = now
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        frame.casting, frame.channelling = now, true
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- (unit, cast, spell, who interrupted it): a cast cut short
        if frame.casting then
            frame.cutAt = now
            frame.cutBy = (not ns.IsSecret(third) and type(third) == "string") and third or nil
        end
        frame.casting, frame.channelling = nil, nil
    elseif event == "UNIT_SPELLCAST_STOP" then
        if frame.casting then
            frame.stopAt = now -- (cut short, unless it succeeded in the same breath: the count looks)
        end
        frame.casting = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if frame.casting and frame.channelling then
            frame.channelCutAt = now -- (a channel that ran its course stops too: only the instant tells)
        end
        frame.casting, frame.channelling = nil, nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local started = frame.castStart
        frame.castStart = nil
        frame.succeededAt = now
        Stomp:OnCast(frame.unit, second, started, now) -- (unit, cast, spell)
    elseif event == "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED" then
        local info = first
        if not ns.IsSecret(info) and type(info) == "table" then
            local category, immune = info.category, info.isImmune
            if not ns.IsSecret(category) and category == stunCategory() then
                frame.stunAt = now
                frame.stunImmune = (not ns.IsSecret(immune)) and immune == true
            end
        end
    elseif event == "UNIT_COMBAT" then
        if not ns.IsSecret(first) and type(first) == "string" then
            frame.combat, frame.combatAt = first, now
        end
    end
end

local function watch(unit)
    local frame = frames[unit]
    if frame then
        return frame
    end
    frame = CreateFrame("Frame")
    frame.unit = unit
    forget(frame)
    for _, event in ipairs(UNIT_EVENTS) do
        if not pcall(frame.RegisterUnitEvent, frame, event, unit) then
            ns.unknownEvents[event] = true
        end
    end
    if Stomp.stunTracker and not pcall(frame.RegisterUnitEvent, frame, STUN_EVENT, unit) then
        ns.unknownEvents[STUN_EVENT] = true
    end
    frame:SetScript("OnEvent", function(self, ...)
        ns.SafeCall(onUnitEvent, self, ...)
    end)
    frames[unit] = frame
    return frame
end

------------------------------------------------------------------------
-- A cast
------------------------------------------------------------------------
function Stomp:OnCast(unit, spellID, started, now)
    if not ns:GetOption("enabled") then
        return
    end
    local seen = Stomp.seen
    seen.casts = seen.casts + 1
    local own = unit == "player"
    local sure = false
    local named = not ns.IsSecret(spellID) and type(spellID) == "number"
    if not own and fact(UnitIsPlayer, unit) == true and fact(UnitIsUnit, unit, "player") ~= true then
        -- another player's cast: what the client lets us see of it, kept for the report
        local ok, _, race = pcall(UnitRace, unit)
        local casts = Stomp.otherCasts
        casts[#casts + 1] = {
            at = type(date) == "function" and date("%H:%M:%S") or "?", unit = unit, who = fact(GetUnitName, unit, true) or "?",
            race = (ok and not ns.IsSecret(race)) and tostring(race) or "secret", took = started and math.floor((now - started) * 100 + 0.5) / 100 or nil,
            spell = named and (spellName(spellID) or spellID) or "hidden",
        }
        if #casts > OWN_CASTS_KEPT then
            table.remove(casts, 1)
        end
    end
    if named then
        seen.named = seen.named + 1
        if own then
            local casts = Stomp.ownCasts
            casts[#casts + 1] = { id = spellID, name = spellName(spellID) or "?", at = type(date) == "function" and date("%H:%M:%S") or "?" }
            if #casts > OWN_CASTS_KEPT then
                table.remove(casts, 1)
            end
        end
        if not isStomp(spellID) then
            return
        end
        sure = true
    else
        seen.hidden = seen.hidden + 1
    end
    if own then
        if not sure then
            return
        end
        seen.own = seen.own + 1
    else
        local mode = ns:GetOption("others")
        if mode == "off" or (not sure and mode ~= "guess") then
            return
        end
        local meGuid, meName = fact(UnitGUID, "player"), fact(GetUnitName, "player", true)
        if fact(UnitIsUnit, unit, "player") == true or (meGuid ~= nil and fact(UnitGUID, unit) == meGuid)
            or (meName ~= nil and fact(GetUnitName, unit, true) == meName) then
            return -- you, through another token (your target, your own nameplate): your own frame has it
        end
        if not sure then
            -- the guess: a cast of half a second, by a Tauren
            if fact(UnitIsPlayer, unit) ~= true then
                return
            end
            local ok, _, race = pcall(UnitRace, unit)
            if not ok or ns.IsSecret(race) or race ~= "Tauren" then
                return
            end
            local took = started and (now - started)
            if not took or took < CAST_MIN or took > CAST_MAX then
                return
            end
            seen.guessed = seen.guessed + 1
        end
    end
    -- one stomp seen through two tokens (your target, who is also party1) is one stomp
    local who = fact(GetUnitName, unit, true) or unit
    local key = fact(UnitGUID, unit) or who
    for other, at in pairs(recent) do
        if now - at > 10 then
            recent[other] = nil
        end
    end
    if recent[key] and now - recent[key] < SAME_CASTER then
        return
    end
    recent[key] = now
    local candidate = { t = now, unit = unit, who = who, guid = fact(UnitGUID, unit), own = own, sure = sure, took = started and (now - started) or nil }
    C_Timer.After(DECIDE_AFTER, function()
        ns.SafeCall(Stomp.Decide, Stomp, candidate)
    end)
end

------------------------------------------------------------------------
-- The count
------------------------------------------------------------------------
local function hasStomp(unit)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if type(get) ~= "function" then
        return false
    end
    local ok, aura = pcall(get, unit, stompName, "HARMFUL")
    if not ok or ns.IsSecret(aura) then
        return false
    end
    return aura ~= nil
end

local function round(value)
    return type(value) == "number" and math.floor(value * 100 + 0.5) / 100 or nil
end

function Stomp:Decide(candidate)
    local from, to = candidate.t - WINDOW_BEFORE, candidate.t + WINDOW_AFTER
    local units = {}
    for unit in pairs(plates) do
        units[#units + 1] = unit
    end
    local shown = #units
    if shown == 0 then
        units[1] = "target" -- no nameplates: the target is all there is to look at
    end
    local auraEvents, stuns, immune, read, considered = 0, 0, 0, 0, 0
    local interrupted, byStomper, channelsStopped, stoppedShort = 0, 0, 0, 0
    for _, unit in ipairs(units) do
        local frame = frames[unit]
        if frame and unit ~= candidate.unit and fact(UnitExists, unit) ~= false and fact(UnitCanAttack, "player", unit) ~= false then
            considered = considered + 1
            if frame.cutAt and frame.cutAt >= from and frame.cutAt <= to then
                interrupted = interrupted + 1
                if frame.cutBy and candidate.guid and frame.cutBy == candidate.guid then
                    byStomper = byStomper + 1
                end
            end
            if frame.channelCutAt and frame.channelCutAt >= from and frame.channelCutAt <= to then
                channelsStopped = channelsStopped + 1
            end
            -- a cast that stopped in the instant without succeeding, and no "interrupted" said for it
            if frame.stopAt and frame.stopAt >= from and frame.stopAt <= to
                and not (frame.cutAt and frame.cutAt >= from and frame.cutAt <= to)
                and not (frame.succeededAt and math.abs(frame.succeededAt - frame.stopAt) <= 0.3) then
                stoppedShort = stoppedShort + 1
            end
            for _, at in ipairs(frame.auras) do
                if at >= from and at <= to then
                    auraEvents = auraEvents + 1
                    break
                end
            end
            if frame.stunAt and frame.stunAt >= from and frame.stunAt <= to then
                if frame.stunImmune then
                    immune = immune + 1
                else
                    stuns = stuns + 1
                end
            end
            if hasStomp(unit) then
                read = read + 1
            end
        end
    end
    local hits, by = auraEvents, "aura changes"
    if read > 0 then
        hits, by = read, "the debuff itself"
    elseif stuns > 0 then
        hits, by = stuns, "stuns reported"
    end
    local cut = interrupted + channelsStopped + stoppedShort
    -- nothing to count on (no enemy nameplate up, no target): a Tauren's half-second cast is a stomp all
    -- the same, and a stomp hits something - called with one mark rather than missed
    local uncounted = considered == 0
    local grade = (hits >= 1 or uncounted) and "nice" or nil
    local record = {
        at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or "?",
        who = candidate.who, own = candidate.own, sure = candidate.sure, took = round(candidate.took),
        plates = shown, considered = considered, auraEvents = auraEvents, stuns = stuns, immune = immune, read = read,
        interrupted = interrupted, interruptedByStomper = byStomper, channelsStopped = channelsStopped, stoppedShort = stoppedShort,
        hits = hits, by = uncounted and "nothing to count on" or by, uncounted = uncounted or nil, cut = cut,
        grade = grade or "none", inCombat = InCombatLockdown() and true or false,
    }
    Stomp.seen.decided = Stomp.seen.decided + 1
    if ns.db then
        ns.db.stomps = ns.db.stomps or {}
        table.insert(ns.db.stomps, record)
        while #ns.db.stomps > STOMPS_KEPT do
            table.remove(ns.db.stomps, 1)
        end
    end
    ns:Log("stomp", record)
    if candidate.own and not ns:GetOption("mine") then
        return -- your own stomp: seen and written down, not called - '/ws mine on' calls it too
    end
    if grade then
        ns:Fire("STOMP", grade, record)
    else
        -- a stomp and no call: say why, every time - a stomp is two minutes apart
        local whose = candidate.own and "your War Stomp" or (tostring(candidate.who) .. "'s War Stomp" .. (candidate.sure and "" or " (a guess)"))
        ns:Print(whose .. " was seen - but no hit was counted on the " .. considered .. " enemy nameplate(s) up. |cffffd100/ws diag|r, then /reload, tells why.")
    end
end

------------------------------------------------------------------------
-- Who is watched
------------------------------------------------------------------------
ns:Listen("LOGIN", function()
    stompName = spellName(STOMP_ID) or stompName
    Stomp.stompName = stompName
    -- the stun tracker's event is asked for only where the client runs the tracker (build 70170 does not)
    Stomp.stunTracker = fact(C_SpellDiminish and C_SpellDiminish.IsSystemSupported) == true
    for _, unit in ipairs({ "player", "target", "focus", "party1", "party2", "party3", "party4" }) do
        watch(unit)
    end
end)

ns:On("GROUP_ROSTER_UPDATE", function()
    if fact(IsInRaid) == true then
        for index = 1, 40 do
            watch("raid" .. index)
        end
    end
end)

ns:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    forget(watch(unit))
    plates[unit] = true
    Stomp.seen.nameplates = Stomp.seen.nameplates + 1
end)

ns:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    plates[unit] = nil
    if frames[unit] then
        forget(frames[unit])
    end
end)

for event, unit in pairs({ PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus" }) do
    ns:On(event, function()
        if frames[unit] then
            forget(frames[unit])
        end
    end)
end

function Stomp:Describe()
    local shown, watched = 0, 0
    for _ in pairs(plates) do
        shown = shown + 1
    end
    for _ in pairs(frames) do
        watched = watched + 1
    end
    local ok, _, race = pcall(UnitRace, "player")
    return {
        stompName = stompName, spell = STOMP_ID, seen = Stomp.seen, nameplatesUp = shown, unitsWatched = watched, stunTracker = Stomp.stunTracker,
        character = fact(GetUnitName, "player", true), race = (ok and not ns.IsSecret(race)) and race or nil,
        knowsStomp = fact(C_SpellBook and C_SpellBook.IsSpellKnown, STOMP_ID),
        ownCasts = Stomp.ownCasts,
        otherCasts = Stomp.otherCasts,
    }
end
