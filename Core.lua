-- AKForeverNiceWarstomp core: namespace, safe calls, event dispatch, message bus, saved variables,
-- session log and slash commands.
--
-- The mission of this addon family, built for the WoW: Forever game mode: minimalistic UI additions that
-- bring out the utility Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth. So:
-- every entry point goes through ns.SafeCall, and every error is kept for the report.
--
-- What this addon is for: a Tauren's War Stomp that lands deserves to be called. NICE WARSTOMP, with an
-- exclamation mark for every target it stunned (NICE WARSTOMP!!!) - out loud, in /yell.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
if string.find(ns.version, "@", 1, true) then
    ns.version = "dev" -- a working copy: the packager has not replaced the @project-version@ token
end
ns.version = (string.gsub(ns.version, "^v", ""))

local PRINT_PREFIX = "|cffd9a066AKForeverNiceWarstomp|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(PRINT_PREFIX .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Secret values. WoW: Forever runs the Midnight-era API, where some values handed to addons may be
-- held but not inspected.
------------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or nil

function ns.IsSecret(value)
    if issecret then
        return issecret(value) and true or false
    end
    return false
end

function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Safe calls: every distinct error is kept for the report.
------------------------------------------------------------------------
ns.errors = {}

local function onError(err)
    err = tostring(err)
    local seen = ns.errors[err]
    ns.errors[err] = (seen or 0) + 1
    if not seen then
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        end
    end
    return err
end

function ns.SafeCall(fn, ...)
    return xpcall(fn, onError, ...)
end

------------------------------------------------------------------------
-- Session log (ring buffer)
------------------------------------------------------------------------
local LOG_MAX = 120
ns.sessionLog = {}

function ns:Log(kind, data)
    local log = ns.sessionLog
    log[#log + 1] = {
        t = math.floor(GetTime() * 1000) / 1000,
        k = kind,
        d = data,
    }
    if #log > LOG_MAX then
        table.remove(log, 1)
    end
end

------------------------------------------------------------------------
-- Internal message bus
------------------------------------------------------------------------
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], ...)
    end
end

------------------------------------------------------------------------
-- Game events: one frame, handlers per event, every handler in a SafeCall
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.unknownEvents = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
        end
    end
    table.insert(eventHandlers[event], fn)
end

------------------------------------------------------------------------
-- Saved variables: ONE account-wide table, the options in it for every character alike - a War Stomp
-- is a War Stomp on all of them.
------------------------------------------------------------------------
local OPTION_DEFAULTS = {
    enabled = true,   -- call War Stomps at all
    yell = true,      -- ... out loud, in /yell (sent inside your next key press: the realm asks for one)
    screen = false,   -- ... and, only if asked for ('/ws screen on'), across the middle of your own screen
    sound = true,     -- ... with a sound (it comes with the text on the screen, never alone)
    others = "guess", -- other Taurens' stomps: "sure" (only when the client names the spell), "guess" (a half-second cast by a Tauren that stuns something), "off"
    mine = false,     -- your own stomps: called too ('/ws mine on'), or not - you know what you did
}

local function initDB()
    local bridge = AKForeverNiceWarstomp_SavedStateBridge
    if type(AKForeverNiceWarstompDB) ~= "table" then
        AKForeverNiceWarstompDB = {}
        ns.savedStateSource = "none (first run, or the client did not load it)"
    elseif type(bridge) == "table" and bridge.table == AKForeverNiceWarstompDB then
        ns.savedStateSource = "bridge addon"
    else
        ns.savedStateSource = "client"
    end
    local db = AKForeverNiceWarstompDB

    db.schema = db.schema or 1
    db.loads = (db.loads or 0) + 1
    db.options = db.options or {}

    ns.db = db
end

function ns:GetOption(key)
    local options = ns.db and ns.db.options
    local value = options and options[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

function ns:SetOption(key, value)
    ns.db.options[key] = value
    ns:Fire("OPTION_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Slash commands: modules register their own sub-commands
------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function ns:RegisterCommand(name, help, fn)
    commands[name] = { help = help, fn = fn }
    commandOrder[#commandOrder + 1] = name
end

SLASH_AKFOREVERNICEWARSTOMP1 = "/akforevernicewarstomp"
SLASH_AKFOREVERNICEWARSTOMP2 = "/ws"
SlashCmdList["AKFOREVERNICEWARSTOMP"] = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    local command = commands[string.lower(name or "")]
    if command then
        ns.SafeCall(command.fn, rest or "")
        return
    end
    ns:Print("v" .. ns.version .. " commands:")
    for _, commandName in ipairs(commandOrder) do
        print("   |cffffd100/ws " .. commandName .. "|r - " .. commands[commandName].help)
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()
end)

ns:On("PLAYER_LOGIN", function()
    ns:Log("login", {
        version = ns.version,
        loads = ns.db and ns.db.loads,
        savedState = ns.savedStateSource,
    })
    ns:Fire("LOGIN")
end)
