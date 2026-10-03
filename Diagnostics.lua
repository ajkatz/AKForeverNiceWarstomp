-- Diagnostics: '/ws diag' writes a report into the saved file - what the client lets this addon see of
-- a War Stomp (is the spell named on other people's casts, are its debuffs readable, does the client
-- report stuns), every stomp taken up with its three counts, every yell and what became of it, every
-- error. Nothing in it is a frame; every value is checked before it is copied so that a secret cannot
-- poison the file.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function sanitize(value, depth)
    depth = depth or 0
    if ns.IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "table" then
        if depth >= 7 then
            return "<too deep>"
        end
        if type(value.GetObjectType) == "function" then
            return "<frame>"
        end
        local copy = {}
        for k, v in pairs(value) do
            local key = k
            if ns.IsSecret(k) then
                key = "<secret key>"
            elseif type(k) ~= "string" and type(k) ~= "number" then
                key = tostring(k)
            end
            copy[key] = sanitize(v, depth + 1)
        end
        return copy
    elseif kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "nil" then
        return nil
    end
    return "<" .. kind .. ">"
end

-- a call's results as a list, or the word "error"
local function ask(fn, ...)
    if type(fn) ~= "function" then
        return "<no such function>"
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return "error: " .. tostring(results[2])
    end
    table.remove(results, 1)
    return results
end

-- what the client says about seeing a War Stomp
function Diagnostics:Client()
    local spell = 20549
    local secrets, diminish, log = C_Secrets or {}, C_SpellDiminish or {}, C_CombatLog or {}
    local stun = Enum and Enum.SpellDiminishCategory and Enum.SpellDiminishCategory.Stun
    local rules = Enum and Enum.SpellDiminishRuleset or {}
    return {
        spellName = ask(C_Spell and C_Spell.GetSpellName, spell),
        castSecrecy = ask(secrets.GetSpellCastSecrecy, spell),      -- 0 never secret, 1 always, 2 depends
        auraSecrecy = ask(secrets.GetSpellAuraSecrecy, spell),
        auraSecretNow = ask(secrets.ShouldSpellAuraBeSecret, spell),
        aurasSecretNow = ask(secrets.ShouldAurasBeSecret),
        stunTracker = {
            supported = ask(diminish.IsSystemSupported),
            tracksStunsPvE = stun and rules.PvE and ask(diminish.ShouldTrackSpellDiminishCategory, stun, rules.PvE) or "<no enum>",
            tracksStunsPvP = stun and rules.PvP and ask(diminish.ShouldTrackSpellDiminishCategory, stun, rules.PvP) or "<no enum>",
        },
        -- (the combat log's events are not for addons here: REGISTERING for one is a forbidden action,
        -- with Blizzard's "blocked" popup - so it is only asked about, never listened to)
        combatLog = {
            restricted = ask(log.IsCombatLogRestricted),
            getter = type(CombatLogGetCurrentEventInfo),
        },
        inCombat = InCombatLockdown() and true or false,
    }
end

function Diagnostics:Collect()
    local db = ns.db or {}
    local report = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "?",
        addonVersion = ns.version,
        savedStateSource = ns.savedStateSource,
        savedVariableLoads = db.loads,
        options = {
            enabled = ns:GetOption("enabled"), yell = ns:GetOption("yell"), screen = ns:GetOption("screen"),
            sound = ns:GetOption("sound"), others = ns:GetOption("others"),
        },
        client = self:Client(),
        stomp = ns.Stomp:Describe(),
        call = ns.Call:Describe(),
        stomps = db.stomps,
        yells = db.yells,
        blockedActions = ns.blockedActions,
        errors = {},
        unknownEvents = ns.unknownEvents,
        session = ns.sessionLog,
    }
    if GetBuildInfo then
        local version, build, buildDate, toc = GetBuildInfo()
        report.build = { version = version, build = build, date = buildDate, toc = toc }
    end
    for message, count in pairs(ns.errors) do
        report.errors[#report.errors + 1] = { message = message, count = count }
    end
    return sanitize(report)
end

-- A report asked for with '/ws diag' is kept; the one taken at logout goes beside it.
function Diagnostics:Save(asked)
    if not ns.db then
        return
    end
    local report = self:Collect()
    if asked then
        report.asked = true
        ns.db.diag = report
        Diagnostics.asked = true
    elseif Diagnostics.asked then
        ns.db.diagAtLogout = report
    else
        ns.db.diag = report
        ns.db.diagAtLogout = nil
    end
end

ns:RegisterCommand("stats", "this session: casts seen, stomps called, yells sent", function()
    local seen, counts = ns.Stomp.seen, ns.Call.counts
    ns:Print(string.format("this session: %d cast(s) seen (%d with the spell named, %d hidden), %d stomp(s) of yours, %d guessed; %d nameplate(s) seen, %d aura change(s); %d call(s) queued, %d yelled, %d heard back, %d blocked, %d stale; keys: %d down (%d of them repeats), %d up.",
        seen.casts, seen.named, seen.hidden, seen.own, seen.guessed, seen.nameplates, seen.auraChanges, counts.queued, counts.sent, counts.heard, counts.blocked, counts.expired, counts.keyDowns, counts.repeats, counts.keyUps))
end)

ns:RegisterCommand("diag", "save a report into the settings file (then /reload, so that it is written to disk)", function()
    Diagnostics:Save(true)
    ns:Print("report saved - /reload (or log out) writes it to disk.")
end)

ns:On("PLAYER_LOGOUT", function()
    Diagnostics:Save()
end)
