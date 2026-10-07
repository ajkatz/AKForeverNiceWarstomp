# Marketplace listing text (copy / paste)

**Name:** AKForeverNiceWarstomp
**Category:** Chat & Communication (second: Combat)
**Game version:** World of Warcraft: Forever (1.60.1)
**License:** MIT
**Summary (one line):** A Tauren near you lands a War Stomp - you yell NICE WARSTOMP, one exclamation mark per target stunned.

## Description

*Part of a small family of addons built for the WoW: Forever game mode, with one mission: minimalistic UI additions that bring out the utility Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth.*

A Tauren's War Stomp that lands deserves to be called. **When a Tauren near you stuns a crowd, you yell NICE WARSTOMP** - with an exclamation mark for every target it caught: `NICE WARSTOMP!!!`

- **Whose stomps:** your group's, your target's, your focus's, anybody's with a nameplate (friendly nameplates on for the Taurens you are not grouped with). Your own are not called - you know what you did (`/ws mine on` calls them too).
- **How it knows:** the client hides what other players cast, so another Tauren's stomp is a guess - a cast of half a second, by a Tauren, that stunned something. The hits are counted on the enemy nameplates around you, five marks at most.
- **The yell:** an addon may not speak in chat on its own on this realm, so the call goes out inside your next key press - a held key's repeats are not presses - and no key is ever swallowed. One yell in three seconds at most; a call nobody pressed a key for in six seconds is dropped.
- **Built not to break things:** nothing of Blizzard's is touched, the combat log is never registered, no timer runs - no "action blocked" popups.

### Commands

- `/ws on` / `off` - call War Stomps (default) / no calls at all
- `/ws yell on|off` - the call in /yell (default on); `/ws screen on` puts it across your screen as well, with a sound (`/ws sound off` for the text alone)
- `/ws mine on|off` - your own stomps too (default off)
- `/ws others guess|sure|off` - other Taurens: the half-second-cast guess (default), only the casts the client names, none
- `/ws test 4` - a NICE WARSTOMP!!!! as if one had landed; `/ws stats`, `/ws diag` - the session's counts; a report for bug reports

Settings are saved for the account: a War Stomp is a War Stomp on every character.

Source and issues: https://github.com/ajkatz/AKForeverNiceWarstomp

## Logo and screenshots

Logo (400 x 400): `..\ForeverBranding\out\AKForeverNiceWarstomp\logo-400.png` (master: `logo-1024.png`).
Screenshot to take in game: the yell in the chat window after a party Tauren's stomp.
