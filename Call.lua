-- Call: saying it. NICE WARSTOMP out loud, in /yell - that is the call. (For whoever wants it as well,
-- '/ws screen on' puts it across the middle of the screen with a sound; off unless asked for.)
--
-- THE YELL. On this realm an addon may not speak in chat on its own (the client asks for a key press:
-- C_ChatInfo.AreOutgoingAddonChatMessagesRestricted). So the call waits for your next key press and
-- goes out inside it: a frame of ours hears every key and passes each one on untouched. While you are
-- playing that is the same instant; a call nobody pressed a key for in six seconds is stale and
-- dropped, and there is one yell in three seconds at most - a field of Taurens is not a chat flood.
--
-- The frame is only allowed to hear keys once the client has confirmed it passes them on; if that
-- cannot be set (it is refused in combat), there is no yell until it can, and never a swallowed key.
--
-- A HELD KEY REPEATS. Walking with W down, the frame hears OnKeyDown again and again - and a repeat is
-- not a key press to the client: a yell sent on one is refused ("Interface action failed because of an
-- AddOn", seen 2026-10-02 17:24 after 1.35 s of walking). And the frame is never told when a key comes
-- up: no OnKeyUp arrives for a frame that passes keys on (seen 2026-10-03 - a session in which every key
-- counted as held after its first press, and nothing was yelled). So a repeat is told by its timing: a
-- held key goes down again within a second at the longest (the keyboard's own repeat delay); a key that
-- has not gone down for longer than that is pressed afresh.
local _, ns = ...

local Call = {}
ns.Call = Call

local TEXT = { nice = "NICE WARSTOMP" }
local COLOUR = { nice = { 1, 0.82, 0 } }
local SCALE = { nice = 1.6 }
local SOUND = { nice = 8959 } -- the raid warning
local MARKS_MAX = 5   -- a stomp stuns five at most; the aura-change count runs higher in a crowd

-- the words, with one exclamation mark for every target hit: NICE WARSTOMP!!! (one at the least - a
-- stomp that was called hit something)
function Call.Text(grade, hits)
    local marks = math.max(1, math.min(MARKS_MAX, tonumber(hits) or 1))
    return (TEXT[grade] or TEXT.nice) .. string.rep("!", marks)
end
local YELL_LIFE = 6   -- seconds a call waits for a key press
local YELL_GAP = 3    -- seconds between two yells, at least
local YELLS_KEPT = 30

local banner, keys
local pending          -- { text, expires, entry }
local lastYell = -100
local armed = false

Call.counts = { queued = 0, sent = 0, expired = 0, tooSoon = 0, heard = 0, blocked = 0, keyDowns = 0, repeats = 0, keyUps = 0 }

local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

------------------------------------------------------------------------
-- On your screen
------------------------------------------------------------------------
local function buildBanner()
    if banner then
        return
    end
    banner = CreateFrame("Frame", "AKForeverNiceWarstompBanner", UIParent)
    banner:SetSize(600, 60)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
    banner:SetFrameStrata("HIGH")
    banner:Hide()
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner.text:SetPoint("CENTER", banner, "CENTER", 0, 0)
    banner.fade = banner:CreateAnimationGroup()
    local alpha = banner.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetStartDelay(1.8)
    alpha:SetDuration(0.9)
    banner.fade:SetScript("OnFinished", function()
        banner:Hide()
    end)
    Call.banner = banner
end

function Call:Show(grade, hits)
    buildBanner()
    local colour = COLOUR[grade] or COLOUR.nice
    banner.text:SetText(Call.Text(grade, hits))
    banner.text:SetTextColor(colour[1], colour[2], colour[3])
    banner:SetScale(SCALE[grade] or SCALE.nice)
    banner.fade:Stop()
    banner:SetAlpha(1)
    banner:Show()
    banner.fade:Play()
    if ns:GetOption("sound") and type(PlaySound) == "function" then
        pcall(PlaySound, SOUND[grade] or SOUND.nice, "Master")
    end
end

------------------------------------------------------------------------
-- Out loud
------------------------------------------------------------------------
local function keep(entry)
    if not ns.db then
        return
    end
    ns.db.yells = ns.db.yells or {}
    table.insert(ns.db.yells, entry)
    while #ns.db.yells > YELLS_KEPT do
        table.remove(ns.db.yells, 1)
    end
end

-- inside a key press (or a slash command, which is one): the waiting call goes out
function Call:Flush(source)
    local call = pending
    if not call then
        return false
    end
    pending = nil
    local now = GetTime()
    local counts = Call.counts
    if now > call.expires then
        counts.expired = counts.expired + 1
        call.entry.result = "nobody pressed a key in time"
        return false
    end
    if now - lastYell < YELL_GAP then
        counts.tooSoon = counts.tooSoon + 1
        call.entry.result = "too soon after the last yell"
        return false
    end
    lastYell = now
    counts.sent = counts.sent + 1
    call.entry.result, call.entry.waited, call.entry.source = "sent", math.floor((now - call.entry.t) * 100 + 0.5) / 100, source
    Call.lastSent = call.entry
    local ok, err = pcall(sendChat, call.text, "YELL")
    if not ok then
        call.entry.result = "error: " .. tostring(err)
    end
    return ok
end

function Call:Queue(grade, record)
    local now = GetTime()
    local entry = { t = now, at = record and record.at, text = Call.Text(grade, record and record.hits), who = record and record.who, result = "waiting for a key press" }
    keep(entry)
    Call.counts.queued = Call.counts.queued + 1
    if pending then
        pending.entry.result = "replaced by the next call"
    end
    pending = { text = entry.text, expires = now + YELL_LIFE, entry = entry }
end

-- our frame hears every key and passes every key on; only then is it allowed to hear them
local function arm()
    if armed or not keys then
        return
    end
    if InCombatLockdown() then
        return -- setting this is refused in combat: PLAYER_REGEN_ENABLED tries again
    end
    local ok = pcall(keys.SetPropagateKeyboardInput, keys, true)
    local passesOn = ok and type(keys.GetPropagateKeyboardInput) == "function" and keys:GetPropagateKeyboardInput() == true
    if not passesOn then
        Call.armProblem = ok and "the client did not confirm that keys are passed on" or "SetPropagateKeyboardInput failed"
        return
    end
    keys:EnableKeyboard(true)
    armed, Call.armProblem = true, nil
end

local FRESH_AFTER = 1.5 -- seconds: a key that has not gone down for this long is pressed afresh; a held
                        -- key repeats within a second at the longest (the keyboard's own repeat delay)

local lastDown = {} -- [key] = when it last went down

local function onKeyDown(_, key)
    if ns.IsSecret(key) or type(key) ~= "string" then
        key = "?"
    end
    local now, counts = GetTime(), Call.counts
    counts.keyDowns = counts.keyDowns + 1
    local last = lastDown[key]
    lastDown[key] = now
    if last and now - last < FRESH_AFTER then
        counts.repeats = counts.repeats + 1 -- held (or pressed again at once): no key press to the client
        return
    end
    if pending then
        Call:Flush("key")
    end
end

-- a key coming up - on a client that says so - makes it fresh again, and is a key event too: the yell
-- goes on it when a held key kept the fresh presses away. Should a client refuse a yell sent on a key's
-- release, that is noted once and releases are left alone from then on.
local function onKeyUp(_, key)
    if ns.IsSecret(key) or type(key) ~= "string" then
        key = "?"
    end
    Call.counts.keyUps = Call.counts.keyUps + 1
    lastDown[key] = nil
    if pending and not Call.keyUpRefused then
        Call:Flush("keyup")
    end
end

ns:Listen("LOGIN", function()
    keys = CreateFrame("Frame", "AKForeverNiceWarstompKeys", UIParent)
    keys:SetScript("OnKeyDown", function(...)
        ns.SafeCall(onKeyDown, ...)
    end)
    keys:SetScript("OnKeyUp", function(...)
        ns.SafeCall(onKeyUp, ...)
    end)
    Call.keys = keys
    arm()
end)

ns:On("PLAYER_REGEN_ENABLED", arm)

-- did it go out? our own yell comes back as a chat event; a refusal as a blocked action
ns:On("CHAT_MSG_YELL", function(_, text, sender)
    local entry = Call.lastSent
    if entry and not ns.IsSecret(text) and text == entry.text and entry.result == "sent" and GetTime() - entry.t < 15 then
        local me = type(GetUnitName) == "function" and GetUnitName("player", true) or nil
        if not ns.IsSecret(sender) and (sender == me or me == nil) then
            entry.result = "heard"
            Call.counts.heard = Call.counts.heard + 1
        end
    end
end)

ns.blockedActions = {}
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    ns:On(event, function(_, addon, fn)
        if ns.IsSecret(addon) or addon ~= ns.name then
            return
        end
        ns.blockedActions[#ns.blockedActions + 1] = { event = event, fn = ns.IsSecret(fn) and "<secret>" or tostring(fn), t = GetTime() }
        local entry = Call.lastSent
        if entry and entry.result == "sent" and GetTime() - entry.t < 15 then
            entry.result = "blocked by the client"
            Call.counts.blocked = Call.counts.blocked + 1
            if entry.source == "keyup" then
                Call.keyUpRefused = true -- a key's release is no key press to this client: not again
            end
        end
    end)
end

------------------------------------------------------------------------
-- A stomp was seen
------------------------------------------------------------------------
ns:Listen("STOMP", function(grade, record)
    if ns:GetOption("screen") then
        Call:Show(grade, record and record.hits)
    end
    if ns:GetOption("yell") then
        Call:Queue(grade, record)
    end
end)

function Call:Describe()
    return {
        armed = armed, armProblem = Call.armProblem, pending = pending and pending.text or nil, counts = Call.counts,
        bannerShown = banner and banner:IsShown() or false,
        chatRestricted = (C_ChatInfo and type(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == "function")
            and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() or nil,
    }
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
local function toggle(option, what)
    return function(rest)
        local word = string.lower(rest or "")
        if word ~= "on" and word ~= "off" then
            ns:Print("usage: /ws " .. option .. " on | off   (now: " .. (ns:GetOption(option) and "on" or "off") .. ")")
            return
        end
        ns:SetOption(option, word == "on")
        ns:Print(what .. ": " .. word .. ".")
    end
end

ns:RegisterCommand("on", "call War Stomps (default)", function()
    ns:SetOption("enabled", true)
    ns:Print("on.")
end)

ns:RegisterCommand("off", "no calls at all", function()
    ns:SetOption("enabled", false)
    ns:Print("off - |cffffd100/ws on|r to call them again.")
end)

ns:RegisterCommand("yell", "'on' (default): the call goes out in /yell, inside your next key press; 'off'", toggle("yell", "the yell"))
ns:RegisterCommand("screen", "'on': the call across the middle of your screen as well, with a sound; 'off' (default): the yell alone", toggle("screen", "the text on your screen"))
ns:RegisterCommand("sound", "'on' (default): a sound with the text on your screen; 'off'", toggle("sound", "the sound"))

ns:RegisterCommand("mine", "'off' (default): your own stomps are not called - you know what you did; 'on': yours too", toggle("mine", "your own stomps"))

ns:RegisterCommand("others", "other Taurens: 'guess' (default) calls a half-second cast by a Tauren that stuns something; 'sure' only when the client names the spell; 'off' calls yours alone", function(rest)
    local word = string.lower(rest or "")
    if word ~= "guess" and word ~= "sure" and word ~= "off" then
        ns:Print("usage: /ws others guess | sure | off   (now: " .. tostring(ns:GetOption("others")) .. ")")
        return
    end
    ns:SetOption("others", word)
    ns:Print("other Taurens: " .. word .. ".")
end)

ns:RegisterCommand("test", "'/ws test' calls a NICE WARSTOMP! as if one had landed, '/ws test 4' one with four hits", function(rest)
    local grade = "nice"
    local hits = tonumber(string.match(rest or "", "%d+")) or 1
    local record = { at = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or "?", who = "test", hits = hits }
    if ns:GetOption("screen") then
        Call:Show(grade, hits)
    end
    if ns:GetOption("yell") then
        Call:Queue(grade, record)
        Call:Flush("slash") -- (a slash command is a key press)
    end
end)
