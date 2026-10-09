# QuadCast Control

A small native macOS app (menu bar + controls window) for the HyperX QuadCast S, covering what NGENUITY does on Windows: lighting effects per ring, brightness, speed, presets, plus software mic gain and headphone volume.

## Demo

<https://github.com/dcoferraz/mac-hyper-x/raw/main/docs/quadcast-control.mp4>

[![QuadCast Control](docs/poster.png)](docs/quadcast-control.mp4)

![The controls window](docs/window.png)

## Requirements

macOS 13 Ventura or newer, and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't needed.

## Build and run

```bash
chmod +x build.sh
./build.sh            # builds build/QuadCast Control.app
./build.sh --install  # same, then copies it to /Applications and opens it
```

Install to /Applications if you want "Open at login" to work reliably.

The app icon is checked in at `Resources/AppIcon.icns`. It's drawn by `Tools/make-icon.swift`, which you only need to run (`swift Tools/make-icon.swift`) if you want to change it.

## What it does

The lighting section offers Solid, Blink, Cycle, Wave, Lightning, Pulse and Off, with up to 8 colors, brightness and speed. Both rings can share one effect or be set separately. Presets are saved locally and picked from a dropdown.

The window shows the mic drawn as it looks, lit with the colors it is actually showing, on the same clock as the hardware. It animates only while an animated effect is selected and the app is frontmost. The window is resizable.

Colors are chosen in a popover attached to the swatch, with hue, saturation and brightness bars. That replaces the system color panel, which is a separate floating window that tends to reopen on whichever display you last used it on.

The window also shows what the mic's own controls are set to: whether the tap sensor has it muted, and which pickup pattern the dial on the back has selected, drawn as the same shape the dial is marked with. Both are readouts; neither can be set from software.

Clicking the menu bar icon opens a panel with the status, a lights switch, the mic gain and headphone sliders, and the presets dropdown, so the usual adjustments don't need the window at all.

The audio section sets the mic's input level and headphone-jack volume through macOS's audio system (the same values as System Settings › Sound). If macOS doesn't expose a software volume for the device, the app says so and the hardware gain dial is the way to go.

## Things to know

The QuadCast S doesn't store custom lighting. The computer has to keep sending colors (about 18 times per second), which is why this is a menu bar app. When you quit it, the mic goes back to its built-in rainbow. This is how the hardware works on Windows too.

The colors go out as raw USB control transfers. macOS leaves the mic's lighting interface without a driver and never publishes it as a HID device, so IOHIDManager can't reach it; the HID interfaces macOS does publish are the mute and volume controls, and they reject a 64-byte report. The app claims the lighting interface exclusively while it runs.

The mic's own controls are its business, but it does say what they're doing, and the app shows it. They sit on a vendor-defined HID interface (usage page 0xFFFF), which macOS does not put behind Input Monitoring, so this needs no permission and shows no prompt. Both arrive as an 8-byte report with ID 5, where byte 1 says which control moved and byte 2 is its new value:

| report | meaning |
| --- | --- |
| `05 10 00` | mute sensor: muted |
| `05 10 01` | mute sensor: not muted |
| `05 11 00`…`03` | pattern dial: bidirectional, cardioid, omnidirectional, stereo |

The dial's values run the opposite way to the icons printed on it, which read stereo, omnidirectional, cardioid, bidirectional from left to right.

The mic will not answer a request for its current state, so the app can't know either value at startup. Until you tap the sensor the status reads "Connected", and after that "Live" or "Muted"; until you turn the dial the pattern reads "Pattern unknown". Muting still makes the firmware switch the rings off, so the hardware tells you too.

The gain dial is analog and reports nothing, so the app can't show its position. The separate "Mic gain" slider is the macOS input level, which is a different thing.

Idle CPU is about 0.3%.

## Troubleshooting

**"QuadCast S not found" while the mic is plugged in.** List the USB IDs with:

```bash
ioreg -p IOUSB -l -w 0 | grep -E '"(USB Product Name|idVendor|idProduct)"'
```

The numbers are decimal. The app knows 0951:171F and the HP-era IDs 03F0:0F8B, 028C, 048C, 068C and 098C. If yours differ, add them to `supportedIDs` in `QuadCastDevice.swift`.

A QuadCast S shows up as **two** USB devices with the same name: an audio one and a lighting one. Only the lighting one matters here. On the unit this was tested against it is 03F0:028C, and the audio sibling is 03F0:0294. You can tell them apart in `ioreg -r -n "HyperX QuadCast S" -l -w 0`: the lighting device has an `IOUSBHostInterface@0` with no driver attached below it.

**Check that the app really has the mic.** While it's running:

```bash
ioreg -r -n "HyperX QuadCast S" -l -w 0 | grep AppleUSBHostInterfaceUserClient
```

That should name `QuadCastControl`. If it names something else, that other process is holding the lighting interface and the app will stay disconnected until it exits.

**Another app is driving the lights.** Quit any other RGB tool (OpenRGB, the `quadcastrgb` CLI) so the two don't fight.

**macOS says the app can't be opened.** Right-click the app › Open, once.

## License

MIT. See [LICENSE](LICENSE).

## Credits

The USB lighting protocol was documented by the open-source QuadcastRGB project (github.com/Ors1mer/QuadcastRGB, GPL-2.0). This app is an independent implementation in Swift; it doesn't include code from that project.
