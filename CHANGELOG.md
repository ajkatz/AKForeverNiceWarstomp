# AKForeverNiceWarstomp

## 0.1.0 - first public release

For **World of Warcraft: Forever** (1.60.1, Interface 16001).

A Tauren's War Stomp that lands deserves to be called: **NICE WARSTOMP**, with an exclamation mark for every
target it stunned (`NICE WARSTOMP!!!`) - out loud, in /yell.

- Every Tauren around you is called: your group, your target, your focus, anybody with a nameplate (turn
  friendly nameplates on for the Taurens you are not grouped with). Your own stomps are seen and kept but
  not called - you know what you did; `/ws mine on` calls them too.
- The client hides what other players cast, so another Tauren's stomp is a guess: a cast of half a second,
  by a Tauren, that stunned something. `/ws others sure` calls only the stomps the client names;
  `/ws others off` calls none but yours.
- The hits are counted on the enemy nameplates up around you - five marks at most. A stomp with nothing to
  count on (no nameplate, no target) is called with one: a Tauren's half-second cast is a stomp.
- An addon may not speak in chat on its own on this realm: the yell goes out inside your next key press. A
  held key repeats, and a repeat is no press to the client, so a key counts once when it goes down and again
  only after a second without it. A call nobody pressed a key for in six seconds is dropped, and there is one
  yell in three seconds at most. `/ws yell off` keeps the call off the channel; `/ws screen on` puts it
  across your screen as well, with a sound.
- `/ws test 4` calls one as if it had landed; `/ws stats` counts the session; `/ws diag` writes a report for
  bug reports - the client's secrecy rules for War Stomp, every stomp with its counts, every yell and what
  became of it.
- Nothing of Blizzard's is touched, no key is ever swallowed, no timer runs, and the combat log is never
  registered (a forbidden action on this client).
