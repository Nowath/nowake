# nowake

A macOS menu bar app that keeps your Mac running with the lid closed.

## How it works

`pmset -a disablesleep 1` is the official power-management flag, and the only
switch that actually prevents clamshell sleep — `caffeinate` and plain
`IOPMAssertion` calls only hold off *idle* sleep, so the Mac still drops off the
moment the lid shuts. (nowake holds an idle-sleep assertion too, as a second layer.)

Closing the lid fires no display-sleep notification — macOS simply drops the
built-in display — so the lid state is read from IOPMrootDomain's
`AppleClamshellState`, polled every 2 seconds. The on/off state is read from the
same registry's `SleepDisabled` key rather than parsed out of `pmset` output,
which doesn't even print that key on every macOS release.

## The panel

Click the menu bar icon for a SwiftUI popover:

- A switch for the mode itself, with elapsed time once it's on
- **Auto-off** — turn off automatically after 30 min / 1 / 2 / 4 hours, with a live countdown
- **Turn off below** — turn off automatically when the battery drops to 10 / 15 / 20 / 30%
- Live lid and power readouts
- **Passwordless turn-off** — see below

Both auto-off settings persist across launches.

The menu bar icon reflects the state: an outlined cup when off, a filled cup
when active, a struck-through laptop when active with the lid closed, and a
warning triangle when the battery is low.

## Authorization

`pmset disablesleep` needs root, so:

- **Turning the mode on** always raises the standard macOS password / Touch ID
  prompt. This is the direction that disables a safety mechanism, so it is never
  made silent.
- **Turning it off** can optionally skip the prompt, via the *Passwordless
  turn-off* switch in the panel. It writes one line to `/etc/sudoers.d/nowake`:

  ```
  <you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
  ```

  That grants exactly one command — the one that restores the macOS default. The
  file is validated with `visudo -c` before it is installed, because a malformed
  sudoers file can lock you out of `sudo` entirely.

Without that rule the auto-off timer and the battery cutoff can only raise a
password prompt and wait — which is useless in the case they exist for, when
you're away from the keyboard. With it, they actually fire.

Remove the rule from the same switch, or by hand:

```
sudo rm /etc/sudoers.d/nowake
```

## Build

```
./build.sh
```

Compiles, assembles `nowake.app`, ad-hoc signs it, and installs it to `~/Applications`.

## If the flag gets stuck

Force-quitting or shutting down while the mode is on leaves the flag set. Launch
nowake and switch it off, or:

```
sudo pmset -a disablesleep 0
```

## Warning

A Mac running with the lid closed can't shed heat through the keyboard. Don't put
it in a bag while the mode is on.
