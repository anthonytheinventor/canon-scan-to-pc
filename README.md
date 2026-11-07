# canon-scan-to-pc

**Use your Canon printer's "Scan → Computer" button with Linux.**

Canon imageCLASS and i-SENSYS multifunction printers have a **Scan → Computer** option on
the touchscreen that sends a scan straight to a computer on your network. Canon only makes
that work on Windows and macOS, through the *MF Scan Utility* / *MF Network Scanner Selector*.
On Linux the computer never shows up in the printer's list.

`canon-scan-to-pc` fixes that. It's a small background service that makes your Linux computer
appear in the printer's **Scan → Computer** list. When you pick it and press **Start**, the scan
is saved to `~/Scans` as a PDF, with a desktop notification.

- Scan from the glass or the document feeder, and multi-page feeder scans become one PDF
- Follows the color choice made at the printer (Color or Black & White)
- Finds the printer on the network by itself
- Removes itself from the printer's list when the computer sleeps or shuts down, and
  comes back on wake-up
- No root, no Canon software, no build step: one Python file plus a systemd user service
- Light: one process, about 16 MB of memory, and practically no CPU while idle (one tiny
  network packet every 10 seconds). Scans are converted in a short-lived helper process, a
  page at a time, so even long feeder scans don't make the service grow

This is a reimplementation of Canon's network protocol (MFNP), worked out from packet
captures of the Windows utility. It is not made or endorsed by Canon.

## Does it work with my printer?

| Printer | Status |
|---|---|
| Canon imageCLASS MF741Cdw / MF743Cdw (i-SENSYS MF741C/743C), firmware 15.01 | ✅ Tested: glass, feeder, color and B&W, sleep and wake-up |
| Other Canon imageCLASS / i-SENSYS models with **Scan → Computer** | Probably. Please [open an issue](../../issues) to report yours |

Requirements:

- The printer has to be supported by SANE's **pixma** backend over the network.
  Check with `scanimage -L` or the
  [SANE supported devices list](http://www.sane-project.org/sane-mfgs.html#Z-CANON).
  Most imageCLASS / i-SENSYS MF models are listed.
- Linux with systemd, Python 3, and these packages (names for Debian, Ubuntu and Linux Mint):

  ```
  sudo apt install sane-utils python3-pil avahi-utils
  ```

  Fedora: `sane-backends python3-pillow avahi-tools`. Arch: `sane python-pillow avahi`.
  `avahi-utils` is only needed to find the printer automatically.

## Install

```
git clone https://github.com/anthonytheinventor/canon-scan-to-pc.git
cd canon-scan-to-pc
./install.sh
```

The installer copies the program to `~/.local/bin`, puts the settings in
`~/.config/canon-scan-to-pc/config.ini`, looks for your printer, and starts the service.
It runs every time you log in.

Then, at the printer: **Scan → Computer →** *your computer's name* **→** choose Color or
Black & White **→ Start**. The file appears in `~/Scans`.

To remove it: `./install.sh --uninstall`

## Settings

Edit `~/.config/canon-scan-to-pc/config.ini`, then run `systemctl --user restart canon-scan-to-pc`.

| Setting | Default | Options |
|---|---|---|
| `host` | found automatically | the printer's IP address or host name; set it if you have several Canon scanners |
| `name` | your computer's host name | what the printer's list shows (ASCII, at most 15 characters) |
| `output_dir` | `~/Scans` | any folder |
| `format` | `pdf` | `pdf` (all pages in one file), `png`, `jpeg` |
| `mode` | `Color` | `Color`, `Gray`, `Lineart`: used when the printer sends a color choice that isn't in `[codes]` |
| `resolution` | `300` | `75`, `150`, `300`, `600` |
| `source` | `auto` | `auto` (feeder if pages are loaded, else glass), `flatbed`, `adf`, `adf-duplex` |
| `paper` | `letter` | `letter`, `legal`, `a4`, `full` |
| `notify` | `yes` | `no` turns off the desktop notification |
| `[codes]` | `01 = Color`, `02 = Gray` | maps the printer's color choice to `Color`, `Gray` or `Lineart` |

Other commands:

```
canon-scan-to-pc --discover    # list Canon scanners on the network
canon-scan-to-pc --scan-now    # scan once with your settings, without using the printer's panel
journalctl --user -u canon-scan-to-pc -f    # watch what it's doing
```

## Troubleshooting

**My computer doesn't appear in the printer's list.**
Check the log (`journalctl --user -u canon-scan-to-pc`). It should say `registered with
<printer> as <NAME>`. If it says no scanner was found, set `host` in the config. The printer
must be reachable on UDP and TCP port 8610, and on TCP port 80 for `source = auto`
(the feeder check).

**The printer says it's waiting, and nothing happens.**
You probably picked an old entry. If the computer lost power or crashed, its old entry can
stay in the list for a while; the service removes it the next time it starts. Pick the other
entry with the same name.

**Scans fail with "Error during device I/O".**
The printer may be in deep sleep. Wake it by touching the screen and try again.

**The log says `unknown code`.**
The printer sent a color choice this program doesn't know yet, such as *Custom 1*. The scan
still works, in your default `mode`. Add the code to `[codes]` and please open an issue
saying which button it was, so it can become a default.

## How it works

Canon's Windows utility talks to the printer over UDP port 8610 with Canon's MFNP protocol, the
same protocol SANE's pixma backend uses for network scanning. Every message starts with a
16-byte header: `"MFNP"`, `0x02` (scanner), a command, two zero bytes, a sequence number, a
session number (0) and the payload length, all big-endian. The *Scan → Computer* list is
managed with command `0x32`, whose payload starts with a type, two zero bytes, a dialog id and
the computer's name (64 bytes, ASCII):

| Step | Type | Rest of the payload | Printer's reply |
|---|---|---|---|
| Discover (command `0x01`) | | | MAC and IP address |
| Hello | 0 | 8 zero bytes | zeros |
| Register | 1 | `u32 0`, `u32 195`, `"User  HOST"` padded to 195 bytes | the dialog id the printer assigns |
| Keep-alive, every 10 s | 2 | `u32 0`, `u32 0x10`, `YYYYMMDDHHMMSS` padded to 16 bytes | `00 00 00 03` + dialog id. When Start was pressed for this computer, byte 2 is `0x80`, followed by `00 00 00 05`, a counter and the color code |
| Acknowledge the scan | 5 | 8 zero bytes | zeros |
| Sign off | 4 | 8 zero bytes | zeros; the computer leaves the list |

After the acknowledgement the scan is fetched over TCP port 8610, which SANE's pixma backend
already knows how to do, so this program runs `scanimage` for that part.

Before the computer sleeps, the service signs off. It holds a logind *delay* sleep inhibitor
and listens for logind's `PrepareForSleep` signal over the system D-Bus, then registers again
after wake-up.

SANE's pixma backend has its own version of this poll (for button support), but it sends the
name as UTF-16 and never registers, so the printer doesn't list the computer. That's the
missing piece this project adds. Details and corrections are welcome.

## Contributing

Reports from other printer models are the most useful thing. Please include the model, its
firmware version, and what the log shows when you scan. If your printer behaves differently,
a packet capture of Canon's Windows utility (Windows has `pktmon` built in) shows exactly
what it expects.

## License

MIT. Canon, imageCLASS and i-SENSYS are trademarks of Canon Inc.; this project is not
affiliated with Canon.
