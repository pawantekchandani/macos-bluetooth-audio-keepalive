# macOS Bluetooth Audio Keepalive

Some Bluetooth speakers on macOS produce **no sound at all** from certain apps —
not from the speaker, not from the built-in speakers — while working perfectly
once any browser tab is playing audio, even muted.

This repo contains a fix, plus a full record of the diagnosis, including the
four approaches that **did not** work. The negative results matter: the obvious
explanation for this symptom is wrong, and the obvious fixes all fail.

## The symptom

- Bluetooth speaker connected and selected as the default output device
- App presses "play" (in the original case, the Claude desktop app's Read Aloud)
- **Silence.** Not from the speaker, not from the laptop
- Disconnect Bluetooth → the same audio plays fine on the built-in speakers
- Open a YouTube tab and **mute it** → the audio immediately works on the
  Bluetooth speaker

That last point is the whole puzzle. Muting in the player doesn't stop the
stream, so the speaker isn't the thing that needs waking.

## What does *not* work

Every one of these was tested and failed:

| Approach | Pipeline | Result |
|---|---|---|
| `afplay` looping a near-silent file | AudioQueue | Fails. Also silently reroutes to built-in speakers |
| `ffmpeg -f audiotoolbox -audio_device_index N` | CoreAudio, pinned to the device | Fails — **while audibly streaming to the speaker** |
| Chrome Web Audio (`AudioContext` + noise) | Web Audio | Fails |
| Swift `AVPlayer` looping a file | AVFoundation | Fails |
| **Chromium `<audio loop>` element** | **media element** | **Works** |

### Why the obvious diagnosis is wrong

The usual explanation is that budget Bluetooth speakers power down their
amplifier when the A2DP stream goes idle, so short bursts get swallowed. That
theory predicts any open audio stream will fix it.

**The ffmpeg test disproves it.** With ffmpeg pinned to the Bluetooth device,
low-level noise was *audible* on the speaker — amplifier awake, link up,
packets flowing — and the target app still produced no sound at all.

So the amplifier-standby story, however well documented in general, was not the
cause here. Whatever macOS requires to route a *new* output stream to the
Bluetooth device, only a browser's media-element pipeline provides it.

`afplay` deserves a specific note: it has **no device-selection flag**
(`-v`, `-t`, `-r`, `-q`, `-d` only), so it always follows the default output
device — and when the Bluetooth link is idle, macOS resolves that to the
built-in speakers. A keepalive built on `afplay` therefore keeps the *laptop
speakers* awake, which is worse than useless.

## The fix

A minimal browser window, in an isolated profile, looping a near-silent 48 kHz
WAV through an `<audio loop>` element. That holds the output device in whatever
state macOS needs, and other apps' audio then routes to the Bluetooth speaker
normally.

Runs as a LaunchAgent at login, with a watchdog that repairs it.

**It sleeps when not needed.** The stream only plays while the app that needs
the speaker (the Claude desktop app by default) is in front, and for five
minutes after it loses focus. Outside that it pauses, so the Bluetooth radio is
left free for mice and keyboards. Change `FOCUS_APP` and `GRACE` at the top of
`src/run.sh` to target a different app or grace period.

**Cost:** ~280 MB RAM, ~0% CPU, and one small window that must stay open.
That is a lot for what it does. It is also the only thing that worked.

## Install

```bash
git clone https://github.com/pawantekchandani/macos-bluetooth-audio-keepalive.git
cd macos-bluetooth-audio-keepalive
./install.sh
```

The installer generates the silent WAV, copies files to
`/Users/Shared/btkeepalive`, writes and loads both LaunchAgents, and puts two
shortcuts on your Desktop. It uses Microsoft Edge by default and falls back to
Chrome; either works, since the mechanism is Chromium's media pipeline.

Uninstall:

```bash
./uninstall.sh
```

## Daily use

Two Desktop shortcuts:

- **Restart BT Keepalive** — restarts everything and reports whether audio is
  genuinely playing
- **Stop BT Keepalive** — stops it when you won't need the speaker for a while.
  It stops the watchdog *first*, otherwise the watchdog would restart the
  keepalive within two minutes

## Reliability notes

In practice this setup failed in three distinct ways, and the watchdog exists
because of them:

1. **The launchd service was evicted from the user domain**, twice — the
   service disappeared entirely, not merely stopped
2. **The browser's auto-updater killed the window**
3. **An unclean shutdown left the profile with `exit_type: Crashed`**, so the
   browser came back on a restore prompt with no audio playing

Number 3 is the nasty one: every process is running and `launchctl list` looks
healthy, but there is no sound. **Checking that the process exists proves
nothing.** The watchdog therefore tests for Chromium's `audio.mojom.AudioService`
subprocess, which exists only while audio is actually in use.

A CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` query was tried as
the health check first and **abandoned** — the built-in output device reports
"running" permanently, so it never detects a failure.

## Does this affect Bluetooth mice and keyboards?

No. Input devices use HID, which has no audio stream, no codec, and never
touches CoreAudio. None of the failing layers exist for them.

One real interaction: while playing, this keepalive streams A2DP continuously,
which shares the 2.4 GHz radio with your other Bluetooth devices. Streaming
around the clock caused measurable mouse and keyboard lag and disconnects,
which is why it now sleeps when the target app is out of focus. If you still
notice lag, stop the keepalive and see whether it clears.

## Is the gate documented in the Bluetooth spec?

No — worth knowing before buying a different speaker.

A2DP/AVDTP defines an explicit state machine (`IDLE` → `OPEN` → `STREAMING`)
driven by signalling commands (`AVDTP_START`, `AVDTP_SUSPEND`). There is no
spec-defined "detect N ms of audio above X dBFS before opening the amplifier."
Amplifier standby is **vendor firmware**, outside the standard, and Apple has
told users the trigger threshold is set by the device manufacturer.

Some vendors publish an auto-*power-off* timer (typically 15–20 minutes of
no audio). That is a different parameter and irrelevant here — the behavior
that matters is sub-second wake latency, which no consumer manufacturer
publishes. There is no spec sheet field you can check before buying.

## Credits

Diagnosed and built collaboratively with Claude Code. The negative results
were as much work as the fix.
