# LilliputKit

Swift package + `lilliput` CLI for controlling Lilliput Q-series (and other RemoteTerminal-compatible) monitors over LAN.

The protocol isn't published by Lilliput. Everything here was recovered from the macOS build of their RemoteTerminal 1.2.x app (github.com/LilliputElectronics/RemoteTerminal) and hasn't been tested against hardware yet. The parts I'm least sure of are marked **unverified**.

## Build

```sh
swift build -c release
swift test
.build/release/lilliput discover
```

Quit RemoteTerminal before running this. Both apps bind UDP port 19522.

## Mac app

```sh
./make-app.sh                      # builds build/Monitor Control.app (ad-hoc signed)
open "build/Monitor Control.app"
```

The app finds monitors when it starts. If a monitor doesn't show up, type its IP into the sidebar. Choose a monitor to get its control panels: Tally & UMD, Picture, Input, Scopes, Exposure & Focus, Geometry, Markers and Audio. With **Live** on, the app re-reads the monitor every 2 s, so front-panel changes show up. **Log** shows every packet sent and received. Sliders send when you let go.

The app and the `lilliput` CLI both need UDP port 19522, so run only one of them (or RemoteTerminal) at a time. On first launch, macOS asks for Local Network access; allow it.

## CLI

```sh
lilliput discover                    # broadcast on every interface
lilliput discover 192.168.0.200      # probe one IP directly (other subnet, routed, etc.)
lilliput get 192.168.1.50
lilliput set 192.168.1.50 tally=red umd="CAM 1" umdon=on
lilliput set 192.168.1.50 input=hdmi falsecolor=arri peaking=on
lilliput set 192.168.1.50 brightness=60 --screen 1
lilliput raw 192.168.1.50 04 00 00 00 04 00 -v     # send any payload by hand
lilliput listen 30                                  # dump traffic, e.g. while RemoteTerminal runs
```

`set` reads the monitor's current state first, then writes only the blocks that changed. Each write replaces a whole block, so this keeps the fields you didn't touch.

## Library

```swift
let t = try UDPTransport()
guard let d = try t.discover().first else { return }
let m = Monitor(transport: t, discovered: d)
try m.refresh()
try m.update { $0.tally = .green; $0.umdText = "CAM 2"; $0.peaking = true }
```

## Protocol reference

**Transport:** UDP. The controller binds port 19522 and sends to the monitor on port 19523. Replies come back to 19522. RS-422 carries the same frames (RemoteTerminal offers 19200, 38400 and 57600 baud).

```
5A  LEN  00  PORT  SCREEN  B5  00  ID  CMD  [payload]  CHK  DD
```
| Field | Meaning |
|---|---|
| LEN | total frame length |
| PORT | 0x20 LAN, 0x00 RS-422 |
| SCREEN | screen bitmask (bit0 = screen 1) |
| B5 | 0xFF in requests; the monitor's machine type in replies |
| ID | device ID; 0xFF = all devices. IDs must be unique on the network. |
| CHK | low byte of the sum of all preceding bytes |

| CMD | Block | Payload |
|---|---|---|
| 00 | Source | 1 byte: input. MV models (machine type 2) send 3 bytes. |
| 01 | Picture | brightness, contrast, saturation, tint, sharpness, backlight, colorTemp |
| 02 | Marker | 3 bytes (bitfields below) |
| 03 | Audio | volume, flags, out-channels |
| 04 | Function | 5 bytes (bitfields below) |
| 05 | UMD | flags, 16 ASCII chars (non-printables become spaces, padded with 0), plus 2 extra bytes on MV models |
| FE | Read settings | no payload. The reply is described below. |
| FF | Discover | no payload. The reply carries the ID in byte 7 and the machine type in byte 5. |

### Values

**Input:** SDI1=0, SDI2=1, SDI3=2, SDI4=3, SFP=4, 2SI=5, SQUARE=6, HDMI=7, VIDEO=12.
**Color temp** (picture[6] bits 0-2): 3200K, 5500K, 6500K, 7500K, 9300K, User = 0–5.

**Marker**
- [0]: bits 0-2 = color (Black, Red, Green, Blue, White); bit 3 = center marker
- [1]: bits 0-2 = safety marker (Off, 95, 93, 90, 88, 85, 80%); bits 4-7 = aspect marker (Off, 16:9, 1.85, 2.35, 4:3, 3:2, 2.0X, 2.0X MAG, Grid, User)
- [2]: bits 0-3 = thickness 1–7; bits 4-6 = aspect mat 0–7

**Audio**
- [0]: volume
- [1]: bits 0-3 = meter/vector channel pair (0 = CH1/2 … 7 = CH15/16); bit 4 = level meter; bit 5 = audio vector
- [2]: bits 0-3 = output channel pair. RemoteTerminal also writes a "left out" value to bits 4-7 on some models.

**Function**
- [0]: bits 0-3 = aspect (Full, 16:9, 1.85, 2.35, 4:3, 3:2, 2.0X, 2.0X MAG, 1.3X, 1.5X); bits 4-5 = scan (Aspect, Pix-to-Pix, Zoom); bit 7 = freeze
- [1]: bits 0-1 = flip (Off, H, V, H/V); bits 2-4 = check field (Off, R, G, B, Mono); bits 5-6 = color bar (Off, 100%, 75%); bit 7 = vectorscope
- [2]: bits 0-1 = H/V delay; bits 2-3 = timecode (Off, LTC, VITC); bits 4-6 = false color (Off, Default, Spectrum, ARRI, RED)
- [3]: bit 0 = exposure; bit 2 = peaking; bits 3-4 = histogram (Off, Y, RGB, Color); bits 5-7 = waveform (Off, Multi, Y, YCbCr, RGB)
- [4]: bits 0-2 = full-screen mode (Off, Y, YCbCr, RGB, Vector, Histogram, Audio); bits 3-4 = display scan (Full, Over, Under); bit 5 = overscan

RemoteTerminal's "Overscan On" button reads function[0] and writes the result into function[4]. That's a bug in the vendor app. LilliputKit sets the bit properly.

**UMD flags** (screen 1)
- bits 0-2 = UMD color. The order is assumed from the manual (White, Red, Green, Blue, Yellow, Cyan, Magenta) and is **unverified**.
- bit 3 = UMD on
- bits 4-5 = tally (Off, Red, Green, Yellow)

On MV models, UMDs 2–4 use the two extra bytes:
- UMD 2: on = bit 3, color = bits 0-2 of the first byte
- UMD 3: on = bit 7, color = bits 4-6 of the first byte
- UMD 4: on = bit 3, color = bits 0-2 of the second byte

### Read-settings (FE) reply

Confirmed on a Q-series monitor (machine type 0x02) by writing blocks and reading them back. Data starts at frame byte 10. This firmware has one extra byte (14) that RemoteTerminal's own parser doesn't account for, so every field after it sits one byte later than the app reads it.

| Data bytes | Contents |
|---|---|
| 0–6 | picture |
| 7 | input |
| 8–10 | marker |
| 11–13 | audio |
| 14 | unknown. It was `01` at first and became `00` when UMD was switched on. |
| 15–19 | function |
| 20 | UMD flags / tally |
| 21–38 | input status text (e.g. "2160p59.94Hz", "No Signal") |
| 39–54 | device name |
| 55–56 | UMD 2–4 bytes |
| 57–58 | multiview source bytes |
| 59 | unknown |

Frame byte 9 is also unknown.

The UMD label text isn't returned, but every UMD/tally write carries it. Pass `umd="…"` whenever you change tally, or the label is cleared.

On this unit, switching UMD on cleared some scope settings (waveform, display scan). That looks like the firmware disabling overlays that would conflict with the UMD.

### Still open

- Slider ranges for picture and volume. The app's UI limits weren't extracted, so 0–100 is a guess.
- What the multiview source bytes mean (the Enable MV and MV Mode controls). LilliputKit sends them back exactly as the monitor reported them.
- Whether the monitor acknowledges writes. RemoteTerminal doesn't wait for one.

A quick `lilliput listen` capture while you click through RemoteTerminal would settle all of these.
