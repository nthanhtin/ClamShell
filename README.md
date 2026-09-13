<p align="center">
  <img src="Assets/icon.png" width="112" alt="ClamShell ribbon icon">
</p>
<h1 align="center">ClamShell</h1>
<p align="center">The iPhone Duo fold effect, on your MacBook.</p>

I vibe coded this just for fun copying the new iPhone Duo.

## What it does

ClamShell reads your MacBook's lid angle and animates the built-in desktop as you
close it. Below your chosen starting angle, the desktop appears to tilt toward
the hinge, blur, and fade to black. Opening the lid reverses the effect while
your desktop is unlocked.

There are two effects:

- **Perspective fold** takes one desktop screenshot for each fold, then warps,
  blurs, and dims that frozen image. It needs Screen Recording permission.
- **Native blur** blurs and dims the live desktop without changing its geometry.
  Apps keep updating underneath, and no Screen Recording permission is needed.

If you stop moving the lid midway, the animation waits **0.5 seconds** by default,
then eases back to the normal desktop. Move the lid again to resume. Motion
smoothing softens the jumps between the sensor's whole-degree readings.

You can try the effect inside the app with the **Preview angle** slider, or turn
on **Follow my lid** to drive that preview with the physical lid. Desktop
animation is enabled separately. The menu-bar icon lets you show the controls,
pause the effect, or quit.

## Try it

Download the app from [Releases](https://github.com/nthanhtin/ClamShell/releases/latest)
for Apple Silicon Macs running macOS 14 or later.

Unzip it, drag **ClamShell.app** into **Applications**, and open it. Choose an effect
and click **Enable desktop animation**. Allow Screen Recording for Perspective
fold when prompted. If macOS blocks the first launch, see the
[opening instructions](.github/release-notes.md).

To build from source, use Xcode with Metal tools and an Apple Development
signing certificate in your keychain.

```sh
bash build.sh
open build/ClamShell.app
```

## Make it yours

- **Angle range:** choose when folding starts and when the screen becomes fully
  dark. Defaults are **85°** and **5°**.
- **Idle timeout:** change how long the lid can stay still before snap-back,
  or set it to Off to keep the effect visible.
- **Movement threshold:** choose how far the lid must move to restart the effect.
  The default **2°** helps ignore sensor jitter.
- **Motion smoothing:** balance responsiveness and softness, from **50–300 ms**.

Timeout, threshold, and smoothing are in **Animation settings** (`⌘,`).
**Start at login** is in the main window. Settings and the enabled/paused state
are remembered between launches.

## A few notes

Tested on an M1 Pro MacBook Pro. Lid sensor access varies by model; manual preview
still works without it. The effect runs on your unlocked desktop, so it won't
appear over the lock screen after sleep. Desktop captures stay in memory.
They aren't saved or uploaded. External displays are left alone, and closing
the lid still puts the Mac to sleep normally.

Built with SwiftUI, Metal, IOKit, and ScreenCaptureKit.
Thanks to [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) and
[mac-angle](https://github.com/ufoym/mac-angle) for the sensor research, and
[iphone-duo](https://github.com/chuspeeism/iphone-duo) for the fold reference.

Tests: `bash test.sh` · Regenerate the icon:
`bash Tools/render-assets.sh`.

## Release

Push a version tag to run the tests and publish an Apple Silicon app ZIP:

```sh
git tag v0.1.1
git push origin v0.1.1
```

No signing secrets needed. Downloads are ad hoc signed and aren't notarized;
see the [release notes](.github/release-notes.md) for opening them.

Licensed under [MIT](LICENSE).
