# AKForeverNiceWarstomp

For **World of Warcraft: Forever** (1.60.1, Interface 16001). A Tauren's War Stomp that lands deserves to be
called: **NICE WARSTOMP**, with an exclamation mark for every target it stunned - out loud, in /yell.

Status: **v0.1.0 (2026-10-03)**, proven in the game: the stomps of the Taurens in your group are heard and
yelled, the hits counted on the nameplates around you.

Install: CurseForge, Wago, or the zip from the GitHub release into `Interface\AddOns\AKForeverNiceWarstomp`.

## What it does

A War Stomp stuns up to five enemies around the Tauren. When one lands near you, you yell
`NICE WARSTOMP!!!` - one mark per target it counted, five at most. Whose stomps:

- **Your group's, your target's, your focus's, and anybody's with a nameplate.** The client only hands an
  addon the units it has a token for, so a Tauren you are not grouped with needs friendly nameplates on
  (Shift-V) or your target on them.
- **Your own are not called** - you know what you did. They are seen and kept in the report; `/ws mine on`
  calls them too.

## How a stomp is seen

Your own casts come with the spell's name. Other players' casts arrive with the spell hidden (a secret
value) unless the client flags it as never secret, so another Tauren's stomp is a **guess**: a cast whose
start and end came half a second apart, by a Tauren, that stunned something around it. `/ws others sure`
takes only the stomps the client names, `/ws others off` only yours.

The hits are counted on the enemy nameplates up: the War Stomp debuff itself where the client lets it be
read (out of combat), else the client's stun tracker where it runs one, else the bare fact that a mob's
auras changed in the stomp's own instant. Every stomp is kept with all three counts (`/ws diag`), so the
report shows which one tells the truth on a given build. A stomp with nothing to count on - no nameplate,
no target - is called with one mark: a Tauren's half-second cast is a stomp.

## The yell

On this realm an addon may not speak in chat on its own: the client wants a key press. So the call waits for
your next key press and goes out inside it - a frame of ours hears every key and passes each one on untouched
(it is only allowed to listen once the client has confirmed that it passes keys on; no key is ever
swallowed). A held key repeats, and a repeat is no press to the client, so a key counts once when it goes
down and again only after a second without it. A call nobody pressed a key for in six seconds is dropped,
and there is one yell in three seconds at most.

`/ws yell off` keeps the call off the channel; `/ws screen on` puts it across the middle of your screen as
well, with a sound (off unless asked for: the yell is the call).

## Commands

| | |
|---|---|
| `/ws on` / `off` | call War Stomps (default) / no calls at all |
| `/ws yell on\|off` | the call in /yell, inside your next key press (default on) |
| `/ws screen on\|off`, `/ws sound on\|off` | the call across your screen, with a sound (default off) |
| `/ws mine on\|off` | your own stomps too (default off) |
| `/ws others guess\|sure\|off` | other Taurens: the half-second-cast guess (default), only casts the client names, none |
| `/ws test [n]` | a `NICE WARSTOMP!` as if one had landed, with n marks |
| `/ws stats` | this session: casts seen, stomps called, yells sent, heard, blocked |
| `/ws diag` | a report into the settings file, then `/reload`: the client's secrecy rules for War Stomp, every stomp with its counts, every yell and what became of it, every error |

`/akforevernicewarstomp` is the long spelling. Settings are saved for the account: a War Stomp is a War
Stomp on every character.

## How it stays out of Blizzard's way

- One event frame per unit token (`RegisterUnitEvent`): the frame knows whose events it hears, and the
  payload is never trusted - a secret value is left alone.
- The combat log is never registered: on this client that is a forbidden action, with Blizzard's "blocked"
  popup. The report only asks the client whether the log is restricted.
- No timer runs; the one `C_Timer.After` is the half second between a cast and its count. Every entry point
  goes through a safe call, and every error is kept for the report.

## Tests

`lua tests/run.lua` from the addon's folder (Lua 5.4; the addon's files run in a 5.1-shaped environment).
The mock models secret values, unit tokens and nameplates, the key frame (presses, repeats, releases) and
the client's refusals - a swallowed key or a forbidden action fails a scenario.
