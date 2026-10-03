-- Scenario tests for AKForeverNiceWarstomp: lua tests/run.lua  (from the addon's folder)
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local passed, failures = 0, {}

local function check(condition, message)
    if not condition then
        error(message or "check failed", 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message and (message .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function scenario(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok and #Mock.errors > 0 then
        ok, err = false, "the addon raised an error: " .. tostring(Mock.errors[1])
    end
    if ok and Mock.swallowed > 0 then
        ok, err = false, "the addon swallowed " .. Mock.swallowed .. " key press(es)"
    end
    if ok and Mock.forbidden > 0 then
        ok, err = false, "the addon did " .. Mock.forbidden .. " forbidden thing(s): the client's \"has been blocked\" popup"
    end
    if ok then
        passed = passed + 1
        Mock.realPrint("  ok    " .. name)
    else
        failures[#failures + 1] = name
        Mock.realPrint("  FAIL  " .. name .. "\n          " .. tostring(err):gsub("\n", "\n          "))
    end
end

-- (most scenarios stomp as the player: they switch the calls for your own stomps on, off out of the box)
local function start(options)
    options = options or {}
    local ns, state = Mock.install(options)
    Mock.login()
    if options.mine ~= false then
        Mock.slash("mine on")
    end
    return ns, state
end

local function printed(text)
    for _, line in ipairs(Mock.printed) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function lastStomp(ns)
    local stomps = ns.db.stomps or {}
    return stomps[#stomps]
end

local function banner()
    return AKForeverNiceWarstompBanner
end

-- the enemies around: nameplates 1..n
local function pull(n)
    for index = 1, n do
        Mock.plate(index)
    end
end

------------------------------------------------------------------------
Mock.realPrint("AKForeverNiceWarstomp scenarios")

scenario("your stomp that stuns something is a NICE WARSTOMP: yelled inside your next key press - and nothing flashes across the screen", function()
    local ns = start()
    pull(3)
    Mock.stomp({ 1, 2 })
    equal(ns.db.yells, nil, "nothing before the count is taken")
    Mock.advance(0.7)
    local stomp = lastStomp(ns)
    equal(stomp.hits, 2); equal(stomp.grade, "nice"); equal(stomp.own, true); equal(stomp.sure, true)
    equal(stomp.plates, 3); equal(stomp.by, "the debuff itself")
    equal(banner(), nil, "no banner: the yell is the call"); equal(#Mock.sounds, 0, "and no sound")
    equal(#Mock.said, 0, "no yell without a key press")
    equal(ns.db.yells[1].result, "waiting for a key press")

    Mock.advance(0.4)
    Mock.key("W")
    equal(#Mock.said, 1); equal(Mock.said[1].text, "NICE WARSTOMP!!", "two hits, two marks"); equal(Mock.said[1].kind, "YELL")
    equal(ns.db.yells[1].result, "heard", "our own yell came back")
    equal(ns.db.yells[1].source, "key"); equal(ns.db.yells[1].waited, 0.5, "from the call to the key press")
    Mock.key("W")
    equal(#Mock.said, 1, "said once")
    equal(ns.Call.counts.sent, 1); equal(ns.Call.counts.heard, 1)
end)

scenario("one exclamation mark for every target hit: four hits, four marks", function()
    local ns = start()
    pull(5)
    Mock.stomp({ 1, 2, 3, 4 })
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 4); equal(lastStomp(ns).grade, "nice")
    Mock.key("SPACE")
    equal(Mock.said[1].text, "NICE WARSTOMP!!!!")

    Mock.advance(10)
    Mock.stomp({ 1, 2, 3, 4, 5 })
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 5)
    Mock.key("SPACE")
    equal(Mock.said[2].text, "NICE WARSTOMP!!!!!")
    equal(ns.Call.Text("nice", 1), "NICE WARSTOMP!"); equal(ns.Call.Text("nice", 0), "NICE WARSTOMP!", "one at the least")
    equal(ns.Call.Text("nice", 3), "NICE WARSTOMP!!!"); equal(ns.Call.Text("nice", 40), "NICE WARSTOMP!!!!!", "five at the most: a stomp stuns five")
end)

scenario("out of the box your own stomps are seen and written down, but not called: you know what you did", function()
    local ns = start({ mine = false })
    equal(ns:GetOption("mine"), false)
    pull(3)
    Mock.stomp({ 1, 2 })
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 2); equal(lastStomp(ns).own, true, "written down")
    Mock.key("W")
    equal(#Mock.said, 0, "not called"); equal(ns.db.yells, nil)
    Mock.advance(10)
    Mock.stomp({})
    Mock.advance(0.7)
    check(not printed("your War Stomp was seen"), "and nothing said about it either")
    -- a party member's stomp is called all the same
    Mock.unit("party1", { name = "Holly Boy", race = "Tauren", player = true })
    Mock.advance(10)
    Mock.cast("party1", Mock.STOMP, 0.5)
    Mock.stunned("nameplate1")
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 1); equal(Mock.said[1].text, "NICE WARSTOMP!")
    -- asked for: yours too
    Mock.slash("mine on")
    check(printed("your own stomps: on"))
    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 2)
    Mock.slash("mine sideways")
    check(printed("usage: /ws mine on | off"))
end)

scenario("a stomp that hits nothing is not called", function()
    local ns = start()
    pull(2)
    Mock.stomp({})
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 0); equal(lastStomp(ns).grade, "none")
    check(not banner() or not banner():IsShown(), "no banner")
    Mock.key("W")
    equal(#Mock.said, 0, "no yell")
    check(printed("no hit was counted on the 2 enemy nameplate(s) up"), "said why there was no call")

    -- another spell of yours is nothing at all
    Mock.cast("player", Mock.BOLT, 1.5)
    Mock.advance(0.7)
    equal(#ns.db.stomps, 1)
end)

scenario("with no nameplates the target is all there is to look at; with nothing at all, a hint - once", function()
    local ns = start()
    Mock.unit("target", { name = "Kobold", hostile = true })
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("target")
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.7)
    equal(lastStomp(ns).plates, 0); equal(lastStomp(ns).hits, 1); equal(lastStomp(ns).grade, "nice")

    Mock.unit("target", nil)
    Mock.advance(10)
    Mock.stomp({})
    Mock.advance(0.7)
    equal(lastStomp(ns).considered, 0); equal(lastStomp(ns).uncounted, true); equal(lastStomp(ns).grade, "nice")
    equal(lastStomp(ns).by, "nothing to count on")
    Mock.key("W")
    equal(Mock.said[#Mock.said].text, "NICE WARSTOMP!", "nothing to count on: called all the same, with one mark")

    -- nameplates up and nothing counted: said too, with the number
    pull(3)
    Mock.advance(10)
    Mock.stomp({})
    Mock.advance(0.7)
    check(printed("no hit was counted on the 3 enemy nameplate(s) up"), "said why")
    -- the stomp under another spell number is the same stomp
    Mock.advance(10)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-9", Mock.STOMP2)
    Mock.advance(0.5)
    Mock.stunned("nameplate1")
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", Mock.STOMP2)
    Mock.advance(0.7)
    equal(lastStomp(ns).grade, "nice", "known by its name")
    local described = ns.Stomp:Describe()
    equal(described.character, "Purrdee Bubson"); equal(described.race, "Tauren"); equal(described.knowsStomp, true)
    equal(described.ownCasts[#described.ownCasts].id, Mock.STOMP2); equal(described.ownCasts[1].name, "War Stomp")
    check(described.seen.auraChanges >= 2 and described.seen.nameplates == 3, "counted for the report")
end)

scenario("the yell waits for a key press - six seconds, no longer - and there is one yell in three seconds", function()
    local ns = start()
    pull(2)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.advance(6.5)
    Mock.key("W")
    equal(#Mock.said, 0, "stale: dropped")
    equal(ns.db.yells[1].result, "nobody pressed a key in time")
    equal(ns.Call.counts.expired, 1)

    -- two stomps close together: the second call replaces the first while it waits
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.unit("party1", { name = "Holly Boy", race = "Tauren", player = true })
    Mock.cast("party1", Mock.STOMP, 0.5)
    Mock.stunned("nameplate2")
    Mock.advance(0.7)
    equal(ns.db.yells[2].result, "replaced by the next call")
    Mock.key("W")
    equal(#Mock.said, 1, "one yell for the two")

    -- and a third right after the yell is too soon
    Mock.advance(1)
    Mock.plateGone(1); Mock.plate(1) -- (a fresh mob: its War Stomp debuff is not the last one's)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 1, "three seconds between yells")
    equal(ns.Call.counts.tooSoon, 1)
    equal(lastStomp(ns).grade, "nice", "the stomp itself was seen all the same")
end)

scenario("another Tauren: the spell is hidden, so a half-second cast by a Tauren that stuns something is taken for one", function()
    local ns = start()
    pull(2)
    Mock.unit("party1", { name = "Holly Boy", race = "Tauren", player = true })
    Mock.cast("party1", Mock.STOMP, 0.5)
    Mock.stunned("nameplate1")
    Mock.advance(0.7)
    local stomp = lastStomp(ns)
    equal(stomp.who, "Holly Boy"); equal(stomp.own, false); equal(stomp.sure, false, "a guess"); equal(stomp.took, 0.5)
    equal(stomp.grade, "nice")
    Mock.key("W")
    equal(Mock.said[1].text, "NICE WARSTOMP!")
    equal(ns.Stomp.seen.guessed, 1); equal(ns.Stomp.seen.hidden, 1)

    -- not a Tauren, not half a second, not a player, nothing stunned: no call
    Mock.advance(10)
    Mock.unit("party2", { name = "Orc Orcson", race = "Orc", player = true })
    Mock.cast("party2", Mock.BOLT, 0.5); Mock.stunned("nameplate1"); Mock.advance(0.7)
    Mock.advance(10)
    Mock.cast("party1", Mock.BOLT, 1.5); Mock.stunned("nameplate1"); Mock.advance(0.7)
    Mock.advance(10)
    Mock.unit("target", { name = "Bull", race = "Tauren", player = false, hostile = false })
    Mock.cast("target", Mock.STOMP, 0.5); Mock.stunned("nameplate1"); Mock.advance(0.7)
    equal(#ns.db.stomps, 1, "none of those")
    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.cast("party1", Mock.STOMP, 0.5); Mock.advance(0.7)
    equal(#ns.db.stomps, 2); equal(lastStomp(ns).grade, "none", "a half-second cast that stunned nothing is not called")
    check(printed("Holly Boy's War Stomp (a guess) was seen - but no hit was counted"), "said so")
    local others = ns.Stomp:Describe().otherCasts
    check(#others >= 3, "other players' casts are kept for the report")
    equal(others[#others].who, "Holly Boy"); equal(others[#others].race, "Tauren"); equal(others[#others].took, 0.5); equal(others[#others].spell, "hidden")

    -- a race the client keeps to itself is nobody's race
    Mock.advance(10)
    Mock.unit("party3", { name = "Mystery Cow", race = "Tauren", raceSecret = true, player = true })
    Mock.cast("party3", Mock.STOMP, 0.5); Mock.stunned("nameplate2"); Mock.advance(0.7)
    equal(#ns.db.stomps, 2)
    equal(ns.Stomp:Describe().otherCasts[#ns.Stomp:Describe().otherCasts].race, "secret", "a race the client keeps to itself is written down as such")

    -- 'sure': only when the client names the spell
    Mock.slash("others sure")
    Mock.advance(10)
    Mock.plateGone(2); Mock.plate(2)
    Mock.cast("party1", Mock.STOMP, 0.5); Mock.stunned("nameplate2"); Mock.advance(0.7)
    equal(#ns.db.stomps, 2, "no guessing")
    Mock.advance(10)
    Mock.cast("party1", Mock.STOMP, 0.5, true); Mock.stunned("nameplate2"); Mock.advance(0.7)
    equal(#ns.db.stomps, 3); equal(lastStomp(ns).sure, true, "named by the client: sure")

    Mock.slash("others off")
    Mock.advance(10)
    Mock.cast("party1", Mock.STOMP, 0.5, true); Mock.stunned("nameplate2"); Mock.advance(0.7)
    equal(#ns.db.stomps, 3, "yours alone")
    Mock.slash("others sideways")
    check(printed("usage: /ws others guess | sure | off"))
end)

scenario("one stomp seen through two unit tokens is one stomp; you through your own target are not another Tauren", function()
    local ns = start()
    pull(1)
    local holly = { name = "Holly Boy", race = "Tauren", player = true, guid = "Player-7" }
    Mock.unit("party1", holly)
    Mock.unit("target", holly)
    Mock.unitEvent("party1", "UNIT_SPELLCAST_START", "party1", "Cast-1", Mock.SECRET)
    Mock.unitEvent("target", "UNIT_SPELLCAST_START", "target", "Cast-1", Mock.SECRET)
    Mock.advance(0.5)
    Mock.stunned("nameplate1")
    Mock.unitEvent("party1", "UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-1", Mock.SECRET)
    Mock.unitEvent("target", "UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", Mock.SECRET)
    Mock.advance(0.7)
    equal(#ns.db.stomps, 1, "once")

    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.unit("target", Mock.state.units.player)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-2", Mock.STOMP)
    Mock.unitEvent("target", "UNIT_SPELLCAST_START", "target", "Cast-2", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("nameplate1")
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", Mock.STOMP)
    Mock.unitEvent("target", "UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", Mock.STOMP)
    Mock.advance(0.7)
    equal(#ns.db.stomps, 2, "your stomp, once"); equal(lastStomp(ns).own, true)
end)

scenario("the count takes the best witness: the debuff read, else the stuns the client reports, else the aura changes", function()
    local ns, state = start()
    pull(4)
    -- in combat the debuffs are secret: the stun tracker speaks
    state.aurasSecret = true
    Mock.stomp({ 1, 2, 3 }, { tracker = true })
    Mock.advance(0.7)
    local stomp = lastStomp(ns)
    equal(stomp.read, 0, "nothing to read"); equal(stomp.stuns, 3); equal(stomp.auraEvents, 3)
    equal(stomp.hits, 3); equal(stomp.by, "stuns reported")

    -- an immune mob's auras change for another reason: the tracker says immune, and it is not a hit
    Mock.advance(10)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("nameplate1", { tracker = true })
    Mock.stunned("nameplate2", { tracker = "immune" })
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.7)
    equal(lastStomp(ns).stuns, 1); equal(lastStomp(ns).immune, 1); equal(lastStomp(ns).hits, 1)

    -- no tracker either: the aura changes are all there is
    Mock.advance(10)
    Mock.stomp({ 1, 2, 3, 4 }, { tracker = "secret" })
    Mock.advance(0.7)
    equal(lastStomp(ns).stuns, 0); equal(lastStomp(ns).hits, 4); equal(lastStomp(ns).by, "aura changes")
    equal(lastStomp(ns).grade, "nice")

    -- an aura change long before the stomp, or after the count's window, is not a hit
    Mock.advance(10)
    Mock.stunned("nameplate3", { debuff = false })
    Mock.advance(2)
    Mock.stomp({ 1 }, { debuff = false })
    Mock.advance(0.5)
    Mock.stunned("nameplate4", { debuff = false })
    Mock.advance(0.2)
    equal(lastStomp(ns).auraEvents, 1); equal(lastStomp(ns).hits, 1)

    -- a nameplate that went and came back is a new mob
    Mock.advance(10)
    state.aurasSecret = false
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("nameplate1")
    Mock.plateGone(1); Mock.plate(1)
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 0, "forgotten with its plate")

    -- friendly nameplates are not hits
    Mock.advance(10)
    Mock.plate(9, { name = "Friendly Guard", hostile = false })
    Mock.stomp({ 9 })
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 0)
end)

scenario("a cast cut short by the stomp is written down: the mob was casting, and its cast was interrupted in the stomp's own instant", function()
    local ns, state = start()
    state.aurasSecret = true
    pull(4)
    -- mob 1 is casting, mob 2 channels, mob 3 finishes its cast just before, mob 4 was interrupted long ago
    Mock.unitEvent("nameplate4", "UNIT_SPELLCAST_START", "nameplate4", "Cast-4", Mock.SECRET)
    Mock.unitEvent("nameplate4", "UNIT_SPELLCAST_INTERRUPTED", "nameplate4", "Cast-4", Mock.SECRET, Mock.SECRET)
    Mock.advance(3)
    Mock.unitEvent("nameplate1", "UNIT_SPELLCAST_START", Mock.SECRET, Mock.SECRET, Mock.SECRET)
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_CHANNEL_START", "nameplate2", "Cast-2", Mock.SECRET)
    Mock.unitEvent("nameplate3", "UNIT_SPELLCAST_START", "nameplate3", "Cast-3", Mock.SECRET)
    Mock.advance(1)
    Mock.unitEvent("nameplate3", "UNIT_SPELLCAST_SUCCEEDED", "nameplate3", "Cast-3", Mock.SECRET)
    Mock.unitEvent("nameplate3", "UNIT_SPELLCAST_STOP", "nameplate3", "Cast-3", Mock.SECRET)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.5)
    for index = 1, 4 do
        Mock.stunned("nameplate" .. index)
    end
    Mock.unitEvent("nameplate1", "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", Mock.SECRET, Mock.SECRET)
    Mock.unitEvent("nameplate1", "UNIT_SPELLCAST_STOP", "nameplate1", "Cast-1", Mock.SECRET)
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_CHANNEL_STOP", "nameplate2", "Cast-2", Mock.SECRET)
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
    Mock.advance(0.7)
    local stomp = lastStomp(ns)
    equal(stomp.hits, 4); equal(stomp.grade, "nice"); equal(stomp.cut, 2)
    equal(stomp.interrupted, 1, "the one that was casting"); equal(stomp.channelsStopped, 1, "and the channel")
    equal(stomp.stoppedShort, 0, "the cast that had just succeeded was not cut short")
    equal(stomp.interruptedByStomper, 0, "the client did not say who")
    Mock.key("W")
    equal(Mock.said[1].text, "NICE WARSTOMP!!!!", "four hits, four marks - one call, whatever was cut short")

    -- where the client names the interrupter, it is checked against the stomper
    Mock.advance(10)
    Mock.unitEvent("nameplate1", "UNIT_SPELLCAST_START", "nameplate1", "Cast-5", Mock.SECRET)
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_START", "nameplate2", "Cast-6", Mock.SECRET)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-7", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("nameplate1"); Mock.stunned("nameplate2")
    Mock.unitEvent("nameplate1", "UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-5", 403, "Player-1")
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_INTERRUPTED", "nameplate2", "Cast-6", 403, "Player-999")
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", Mock.STOMP)
    Mock.advance(0.7)
    equal(lastStomp(ns).interrupted, 2); equal(lastStomp(ns).interruptedByStomper, 1, "yours; the other one was somebody's kick")

    -- an interrupt with no cast before it, and one outside the stomp's instant, are not the stomp's
    Mock.advance(10)
    Mock.unitEvent("nameplate3", "UNIT_SPELLCAST_INTERRUPTED", "nameplate3", "Cast-8", Mock.SECRET, Mock.SECRET)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    equal(lastStomp(ns).interrupted, 0); equal(lastStomp(ns).grade, "nice")

    -- a client that only says "stopped" for a stunned caster: a cast that stopped in the instant
    -- without having succeeded counts just the same
    Mock.advance(10)
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_START", "nameplate2", "Cast-9", Mock.SECRET)
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-10", Mock.STOMP)
    Mock.advance(0.5)
    Mock.stunned("nameplate2")
    Mock.unitEvent("nameplate2", "UNIT_SPELLCAST_STOP", "nameplate2", "Cast-9", Mock.SECRET)
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", Mock.STOMP)
    Mock.advance(0.7)
    equal(lastStomp(ns).stoppedShort, 1); equal(lastStomp(ns).interrupted, 0); equal(lastStomp(ns).hits, 1)
    equal(lastStomp(ns).grade, "nice"); equal(lastStomp(ns).cut, 1)
    Mock.slash("test 2")
    equal(Mock.said[#Mock.said].text, "NICE WARSTOMP!!")
end)

scenario("the keyboard: no key is ever swallowed, and the frame hears keys only once the client confirms it passes them on", function()
    -- logging in during a fight: passing keys on cannot be set, so the frame does not listen yet
    local ns, state = start({ combat = true })
    equal(ns.Call:Describe().armed, false)
    check(not AKForeverNiceWarstompKeys.__keyboard, "not listening")
    Mock.key("W")
    state.combat = false
    Mock.fire("PLAYER_REGEN_ENABLED")
    equal(ns.Call:Describe().armed, true, "armed when the fight is over")
    equal(AKForeverNiceWarstompKeys.__propagate, true); equal(AKForeverNiceWarstompKeys.__keyboard, true)
    Mock.key("W")

    -- a client that does not confirm: never listening; the slash command still yells (it is a key press)
    ns = start({ propagateIgnored = true })
    equal(ns.Call:Describe().armed, false)
    check(ns.Call:Describe().armProblem:find("did not confirm", 1, true), ns.Call:Describe().armProblem)
    check(not AKForeverNiceWarstompKeys.__keyboard, "not listening")
    pull(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 0, "no yell: no key is heard")
    equal(lastStomp(ns).grade, "nice", "the stomp was seen")
    Mock.slash("test")
    equal(#Mock.said, 1)
end)

scenario("a held key repeats, and a repeat is no key press: the yell waits for a fresh one", function()
    local ns = start()
    pull(2)
    Mock.keyDown("W") -- walking: W is down before the stomp
    Mock.stomp({ 1, 2 })
    Mock.hold("W", 0.7)
    Mock.keyRepeat("W")
    Mock.keyRepeat("W")
    equal(#Mock.said, 0, "a repeat of the held key does not carry the yell")
    equal(ns.db.yells[1].result, "waiting for a key press")
    Mock.keyDown("S") -- another key pressed while W is held: fresh
    equal(#Mock.said, 1, "a fresh press does"); equal(ns.db.yells[1].result, "heard")
    Mock.keyUp("S"); Mock.keyUp("W")
    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 2, "W again, after it came up")
    -- a key held however long never counts as fresh: its repeats (what a long hold's "down" events are to
    -- the client) are not key presses - seen 2026-10-02 22:59, a yell refused on a "fresh" repeat
    Mock.keyDown("W")
    Mock.hold("W", 30)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.hold("W", 0.7)
    Mock.keyRepeat("W")
    equal(#Mock.said, 2, "a repeat after thirty seconds of holding is still a repeat")
    Mock.keyUp("W")
    equal(#Mock.said, 3, "the key coming up carries it")
    equal(ns.Call.counts.expired, 0)
    Mock.keyUp("W")
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.keyDown(Mock.SECRET)
    equal(#Mock.said, 3, "a key the client keeps secret is a key all the same")
    Mock.keyUp(Mock.SECRET)
end)

scenario("you, seen through your own nameplate or your target, are not another Tauren", function()
    local ns = start({ mine = false })
    pull(2)
    -- your personal nameplate: your own unit, under a nameplate token the client will not compare
    Mock.plate(9, { name = "Purrdee Bubson", race = "Tauren", player = true, guid = "Player-1", hostile = false, compareSecret = true })
    Mock.unitEvent("player", "UNIT_SPELLCAST_START", "player", "Cast-1", Mock.STOMP)
    Mock.unitEvent("nameplate9", "UNIT_SPELLCAST_START", "nameplate9", "Cast-1", Mock.SECRET)
    Mock.advance(0.5)
    Mock.stunned("nameplate1")
    Mock.unitEvent("player", "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", Mock.STOMP)
    Mock.unitEvent("nameplate9", "UNIT_SPELLCAST_SUCCEEDED", "nameplate9", "Cast-1", Mock.SECRET)
    Mock.advance(0.7)
    equal(#ns.db.stomps, 1, "one stomp, yours"); equal(lastStomp(ns).own, true)
    Mock.key("W")
    equal(#Mock.said, 0, "and not called: yours are not")
end)

scenario("a key coming up carries the yell too - unless this client refuses that, which it says once", function()
    local ns = start()
    pull(2)
    Mock.keyDown("W")
    Mock.stomp({ 1 })
    Mock.hold("W", 0.7)
    Mock.keyRepeat("W")
    equal(#Mock.said, 0)
    Mock.keyUp("W")
    equal(#Mock.said, 1, "W came up: the yell went on it"); equal(ns.db.yells[1].source, "keyup"); equal(ns.db.yells[1].result, "heard")

    -- a client that does not count releases: refused once, then left alone
    ns = start({ keyUpBlocked = true })
    pull(2)
    Mock.keyDown("W")
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.keyUp("W")
    equal(ns.db.yells[1].result, "blocked by the client"); equal(ns.Call.keyUpRefused, true)
    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.keyDown("W")
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.keyUp("W")
    equal(ns.db.yells[2].result, "waiting for a key press", "releases are left alone now")
    Mock.keyDown("S")
    equal(ns.db.yells[2].result, "heard", "a fresh press still does")
    Mock.keyUp("S")
end)

scenario("a client that never says when a key comes up (this one): a held key is known by its repeats, a fresh press by the second without it", function()
    -- seen 2026-10-03: no OnKeyUp ever arrived, and a build that waited for releases yelled nothing all session
    local ns = start({ noKeyUps = true })
    pull(2)
    Mock.key("W"); Mock.key("1"); Mock.key("2") -- the keys of the session, each pressed once, none seen coming up
    Mock.advance(5)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 1, "pressed again after seconds: fresh, whatever the frame was not told"); equal(ns.db.yells[1].result, "heard")
    -- walking: W held for twenty seconds, the stomp in the middle - its repeats carry nothing, a tap of 1 does
    Mock.advance(10)
    Mock.keyDown("W")
    Mock.hold("W", 20)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.hold("W", 0.7)
    equal(#Mock.said, 1, "the held key's repeats are no presses")
    Mock.hold("W", 2)
    Mock.key("1")
    equal(#Mock.said, 2, "a tap of another key is"); equal(ns.db.yells[2].source, "key")
    Mock.hold("W", 5)
    -- W let go (unseen) and pressed again a little later: fresh after a second without it
    Mock.advance(1.2)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 3, "W again, seconds after its last repeat: fresh")
    -- mashing one key: the first press of the run is fresh, the rest within the second are not
    Mock.advance(10)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    for _ = 1, 6 do
        Mock.key("2")
        Mock.advance(0.3)
    end
    equal(#Mock.said, 4, "the first of the run carried it")
    equal(ns.Call.counts.keyUps, 0, "no key ever came up"); check(ns.Call.counts.repeats > 600, "the repeats were counted: " .. ns.Call.counts.repeats)
    equal(ns.Call.counts.blocked, 0, "and nothing was ever refused")
end)

scenario("a client that refuses the yell even inside a key press: noted, no error", function()
    local ns = start({ chatBlockedEvenInKeyPress = true })
    pull(1)
    Mock.stomp({ 1 })
    Mock.advance(0.7)
    Mock.key("W")
    equal(#Mock.said, 0)
    equal(ns.db.yells[1].result, "blocked by the client")
    equal(ns.Call.counts.blocked, 1)
    equal(#ns.blockedActions, 1)
end)

scenario("the commands: off, the yell, a test - and the text across the screen for whoever asks for it", function()
    local ns = start()
    pull(1)
    Mock.slash("test")
    equal(#Mock.said, 1, "a slash command is a key press: said at once"); equal(Mock.said[1].text, "NICE WARSTOMP!")
    equal(banner(), nil, "the yell alone, out of the box"); equal(#Mock.sounds, 0)
    Mock.advance(5)
    Mock.slash("test 4")
    equal(Mock.said[2].text, "NICE WARSTOMP!!!!")

    -- asked for: the text across the screen, with a sound
    Mock.slash("screen on")
    check(printed("the text on your screen: on"))
    Mock.advance(5)
    Mock.slash("test")
    check(banner() and banner():IsShown(), "the banner is up")
    equal(banner().text:GetText(), "NICE WARSTOMP!"); equal(banner():GetScale(), 1.6); equal(Mock.sounds[1], 8959)
    Mock.advance(5)
    Mock.slash("test 3")
    equal(banner().text:GetText(), "NICE WARSTOMP!!!"); equal(banner():GetScale(), 1.6); equal(Mock.sounds[2], 8959)
    equal(#Mock.said, 4)

    Mock.advance(5)
    Mock.slash("yell off")
    check(printed("the yell: off"))
    Mock.plateGone(1); Mock.plate(1)
    banner():Hide()
    Mock.stomp({ 1 }); Mock.advance(0.7); Mock.key("W")
    equal(#Mock.said, 4, "no yell")
    check(banner():IsShown(), "the screen alone")
    Mock.slash("yell on")

    Mock.slash("sound off")
    local sounds = #Mock.sounds
    Mock.advance(5)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 }); Mock.advance(0.7); Mock.key("W")
    equal(#Mock.sounds, sounds, "no sound"); equal(#Mock.said, 5)
    Mock.slash("screen off")
    banner():Hide()
    Mock.advance(5)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 }); Mock.advance(0.7); Mock.key("W")
    equal(banner():IsShown(), false, "no banner"); equal(#Mock.said, 6, "the yell alone")
    Mock.slash("sound sideways")
    check(printed("usage: /ws sound on | off"))

    Mock.slash("off")
    Mock.advance(5)
    Mock.plateGone(1); Mock.plate(1)
    Mock.stomp({ 1 }); Mock.advance(0.7); Mock.key("W")
    equal(#Mock.said, 6, "off: nothing")
    Mock.slash("on")
    Mock.slash("stats")
    check(printed("this session:"))
    Mock.slash("")
    check(printed("/ws others"), "the commands are listed")

    -- the options are kept
    local db = AKForeverNiceWarstompDB
    ns = start({ db = db })
    equal(ns:GetOption("sound"), false); equal(ns:GetOption("screen"), false)
    equal(ns:GetOption("others"), "guess"); equal(ns:GetOption("mine"), true, "kept")
end)

scenario("secret values everywhere: nothing is compared, nothing breaks", function()
    local ns, state = start()
    state.aurasSecret = true
    Mock.fire("NAME_PLATE_UNIT_ADDED", Mock.SECRET)
    Mock.fire("NAME_PLATE_UNIT_REMOVED", Mock.SECRET)
    pull(2)
    Mock.unit("target", { name = "Somebody", race = "Tauren", player = true })
    Mock.unitEvent("target", "UNIT_SPELLCAST_START", Mock.SECRET, Mock.SECRET, Mock.SECRET)
    Mock.advance(0.5)
    Mock.unitEvent("nameplate1", "UNIT_AURA", Mock.SECRET, Mock.SECRET)
    Mock.unitEvent("nameplate1", "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED", Mock.SECRET, Mock.SECRET)
    Mock.unitEvent("nameplate1", "UNIT_COMBAT", Mock.SECRET, Mock.SECRET, Mock.SECRET, Mock.SECRET, Mock.SECRET)
    Mock.unitEvent("nameplate2", "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED", "nameplate2", { category = Mock.SECRET, isImmune = Mock.SECRET })
    Mock.unitEvent("target", "UNIT_SPELLCAST_SUCCEEDED", Mock.SECRET, Mock.SECRET, Mock.SECRET)
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 1, "the aura change alone was counted"); equal(lastStomp(ns).who, "Somebody")
    Mock.fire("CHAT_MSG_YELL", Mock.SECRET, Mock.SECRET)
    Mock.fire("ADDON_ACTION_BLOCKED", Mock.SECRET, Mock.SECRET)
    Mock.fire("PLAYER_TARGET_CHANGED")
    Mock.fire("PLAYER_FOCUS_CHANGED")
    state.raid = true
    Mock.fire("GROUP_ROSTER_UPDATE")
    equal(ns.Stomp:Describe().unitsWatched >= 47, true, "the raid is watched")
end)

scenario("the stun tracker: asked for only where the client runs it (build 70170 does not), and never an event that is not for addons", function()
    -- this build: the tracker is off, so its event is not asked for at all
    local ns, state = start({ stunTracker = false })
    equal(ns.Stomp:Describe().stunTracker, false)
    state.aurasSecret = true
    pull(2)
    Mock.stomp({ 1, 2 }, { tracker = true })
    Mock.advance(0.7)
    equal(lastStomp(ns).stuns, 0, "not listened to"); equal(lastStomp(ns).hits, 2); equal(lastStomp(ns).by, "aura changes")

    -- a client that runs the tracker but does not know the event by that name: said so, no error
    ns = start({ unknownEvents = { "UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED" } })
    equal(ns.unknownEvents["UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED"], true)
    pull(2)
    Mock.stomp({ 1, 2 })
    Mock.advance(0.7)
    equal(lastStomp(ns).hits, 2)
    equal(Mock.forbidden, 0, "nothing forbidden was asked for: no popup")
end)

scenario("diagnostics and logout run; the report is SavedVariables-safe and holds no frame", function()
    local ns = start()
    pull(2)
    Mock.stomp({ 1, 2 }); Mock.advance(0.7); Mock.key("W")
    Mock.slash("diag")
    check(printed("report saved"))
    Mock.fire("PLAYER_LOGOUT")
    local report = AKForeverNiceWarstompDB.diag
    equal(report.asked, true); check(AKForeverNiceWarstompDB.diagAtLogout, "the logout's report goes beside it")
    equal(report.addonVersion, "0.1.0-test"); equal(report.build.build, "70170")
    equal(report.client.spellName[1], "War Stomp"); equal(report.client.castSecrecy[1], 2)
    equal(report.client.stunTracker.supported[1], true); equal(report.client.combatLog.restricted[1], true)
    equal(#report.blockedActions, 0, "nothing blocked")
    equal(report.stomp.seen.own, 1); equal(report.call.armed, true); equal(report.call.counts.heard, 1)
    equal(#report.stomps, 1); equal(report.stomps[1].grade, "nice")
    equal(report.yells[1].result, "heard")
    equal(report.options.others, "guess")

    local function walk(value, path)
        local kind = type(value)
        check(kind == "table" or kind == "string" or kind == "number" or kind == "boolean", path .. " holds a " .. kind)
        if kind == "table" then
            check(rawget(value, "__kind") == nil, path .. " is a frame")
            for k, v in pairs(value) do
                walk(v, path .. "." .. tostring(k))
            end
        end
    end
    walk(AKForeverNiceWarstompDB, "AKForeverNiceWarstompDB")
end)

scenario("the stomps are a ring of forty; the version: the packager's stamp, a working copy, a release tag", function()
    local ns = start()
    pull(1)
    for _ = 1, 45 do
        Mock.plateGone(1); Mock.plate(1)
        Mock.stomp({ 1 })
        Mock.advance(5)
    end
    equal(#ns.db.stomps, 40)
    equal(#ns.db.yells, 30)
    ns = start({ version = "@project-version@" })
    equal(ns.version, "dev")
    ns = start({ version = "v0.1.0" })
    equal(ns.version, "0.1.0")
end)

------------------------------------------------------------------------
Mock.realPrint("")
Mock.realPrint(passed .. " passed, " .. #failures .. " failed")
if #failures > 0 then
    os.exit(1)
end
