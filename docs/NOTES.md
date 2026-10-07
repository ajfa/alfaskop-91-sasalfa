# Notes

What was measured while connecting the emulated Alfaskop 91 to the Univac 90/30
emulator. Addresses are those of the running system; nothing here is copied
from Ericsson's or Sperry's software.

## SASALFA on the wire

SASALFA, as the SAS diskettes speak it, is the Uniscope 100 line procedure of
Sperry Univac's UP-7779 (Uniscope 100 Communications Control Procedures) on a
bisync line:

* ASCII, 7 bits with odd parity, `SYN SYN` before every message.
* Messages are `SOH RID SID DID STX text ETX BCC`, where BCC is the XOR of
  everything after SOH up to and including ETX. Polls and acknowledgements have
  no STX.
* "No traffic" is `EOT EOT ETX BCC`.
* The terminal acknowledges host text with `DLE 1` on the next poll. The host
  must acknowledge that with a poll carrying `DLE 1` (rule 4); if it does not,
  the terminal answers every poll with a reply request, `DLE ENQ`, until it
  gets one (rule 9).

Addresses in this configuration:

| field | value | where it comes from |
|---|---|---|
| RID | `22` | the `C9B/ADDRESS` setting on the SAS diskettes; U9030's adapter on port 9036 uses the same |
| SID | `51` | first station |
| DID | `70` | polls; text to `70` goes to the message line (row 23) |
| DID | `72` | the screen of the display unit at station 2 |

The A91 answers broadcast polls (RID `20`) but accepts text only at its own
RID. The line is configured as type `V`, a leased line, and the receiver drops
everything while DCD is off.

The A91 sends a screen as `ESC VT y x 'B' SI text`: the cursor address of the
start of the transmission, then the text up to the cursor. A UTS or U200 puts
NUL where the A91 puts `B`, and IMS does not find the transaction code
otherwise, so the bridge replaces it. Transmission starts at home, or at the
last start of entry (SOE, `RS`), and ends at the cursor; a transaction has to
be typed from home.

## The A91 side

The 68000 controller (CP) runs the host line on channel B of its MK68564. In
the SAS configuration it programs that channel for bisync, 7 bits plus parity,
with `SYN 16`. The terminal data then goes to the display unit over the TCC
two-wire line, wrapped in a TCC message with a type byte; the DU program
interprets the Uniscope stream itself. Message type 7 is the message line: it
sets `$451E` in the DU and puts the text on row 23.

The CP picks the station for each TCC channel by writing `F0FFF7` with
`channel << 6 | station`. The 3270 (R4A) diskettes use station 0; the SAS
diskettes talk to stations 1 to 7 and 13 to 15. The driver now has a CONFIG
setting, "Display unit station", and the DU hears only frames for its station.

## D4GSAS, the display unit program

The SAS emulation diskette loads D4GSAS into the DU's 6800. Entry points in the
loaded image:

| address | what |
|---|---|
| `3F83` | main loop |
| `9A6B` | `DUOVLY` overlay |
| `C246` | `DUINIT` |
| `415D` | text loop: printable characters, `RS` and the cursor |
| `421B` | `ESC` handling, through the table at `DD00` (index) and `44D0` (handlers) |
| `442E` | control characters, through the table at `DB00` (index) and `44FA` (handlers) |
| `50FE` | function keys, through the table at `540B` |

Screen model: base at `$DF:$E0` = `7060`, `$E1` = 160 bytes per row, 24 rows,
**two bytes per cell, attribute then character**. The CRTC start address is
`3830`, and the video fetches from twice the CRTC address. The status line,
row 24, stays at one byte per cell at `7FB0`. D4GSAS selects this mode with bit
5 of port B of the DU's MIC PIA (`F7C6`): SAS writes `29` or `39`, the 3270
program writes `89`. The MAME driver ignored that port, which is why the first
SAS screens looked like one double width line.

The cursor is `$E9:$EA` (a cell address).

### Control characters in host text

Measured by sending one row per character and reading the cells back:

| character | effect |
|---|---|
| `FS` (1C) | stores delimiter `A8` with attribute `BC` (protected field) |
| `EM` (19) | stores delimiter `88` with attribute `BC` |
| `GS` (1D) | stores delimiter `80`; the next cell gets attribute `84` (unprotected) |
| `SUB` (1A) | stores delimiter `A0`; the next cell gets attribute `84` |
| `RS` (1E) | stores the SOE character `1A` |
| `SO`, `SI`, `US`, `DC1`, `DC3` | nothing visible |

From the dispatch tables, named as in the Uniscope manual: `HT` is tab, `CR`
cursor return, `DC2` print, `DC4` lock keyboard. `ESC VT y x` addresses the cursor, `ESC e` homes it,
`ESC a`, `ESC b` and `ESC l` share the erase handler, `ESC j` and `ESC k` are
insert and delete line, `ESC M` erases.

In Uniscope terms (UP-7807, the programmer's reference), `FS` and `GS` are the
start and end blink markers, and protected fields are delimited by `SO` and
`SI`. D4GSAS ignores `SO` and `SI` and builds protected fields from `FS`/`EM`
and `GS`/`SUB` instead.

### Attributes

D4GSAS writes only two attribute values, both constants in its image:
`84` at the start of an unprotected field (`$47C7`) and `BC` for a protected
one (`$47C8`), plus `AND CF` to drop the protection bits. Bits `30` set mean
protected: the key handler refuses a data key there (`5025`). Nothing in the
program writes a reverse, underline, blink or intensity attribute, so there is
nothing of that kind to draw. A Uniscope shows protected text like any other;
the driver does the same, and shows the delimiter characters blank. What the
DU's video hardware does with the attribute bits is not known.

### Keyboard

The DU program receives each key as a class (`$0263`) and a code (`$0264`).
Class `& 3` = 2 goes to the function table at `540B`, indexed by the code.
For the cursor keys:

| key | MAME name | class/code | effect |
|---|---|---|---|
| 39, 90 | Cursor Left | `12/01` | one cell left, wraps |
| 115 | Cursor Right | `12/02` | one cell right |
| 23 | Cursor Up | `12/03` | one row up, wraps from row 0 to row 23 |
| 87 | Cursor Down | `12/04` | one row down |
| 91 | Cursor New Line | `12/05` | start of the next row |
| 95, 106 | Line Start | `12/07` | |
| 17, 98 | Home | `12/08` | to the start of the next field (`5909`); with no fields it stays put |
| **55** | Key 55 (0206) | `52/06` | **cursor home** (`5D0E`) |
| 103 | Enter | `72/1F` | transmit |

So the Home key of the 3270 layout is not Home in SAS; key 55 is. The patch
maps key 55 to keypad `/`. Other classes seen: `42/23` for the PA keys, PF13
to PF24, Clear and Reset (all `23`, which D4GSAS ignores), `51/xx` for PF1 to
PF10, `62/xx` for Insert, Tab, Back Tab, Field Mark, Print and the second
Enter, `72/14` for Erase Input.

## The 90/30 side

U9030 is Steve Boyd's Univac 90/30 emulator, running OS/3 with ICAM and IMS.

* Its Uniscope adapter listens on TCP 9034 (RID `21`) and 9036 (RID `22`, the
  IMS line). The adapter answers ICAM's polls itself; only text crosses the
  connection. It opens with `FF 20`, then `FF FF RID SID`, and each text is
  `STX ... ETX`.
* The system console is TCP 9030: output is `STX ... ETX`; input is `BEL ETX`
  for attention, or `STX ESC VT row col NUL SI RS text ETX`. Console commands
  need a trailing space (`C2 `, `RV IMS `).
* U9030 starts its console client, `U9030Console.exe`, by itself. A stand-in
  that exits at once leaves the console port to `console.py`.
* IPL is a VCL button. Posting `WM_COMMAND`/`BN_CLICKED` to its parent presses
  it with the window hidden; `SendMessage` blocks, because the handler then
  runs the CPU.
* The ports listen on all interfaces, so Windows Firewall may ask; cancelling
  is fine, everything here is local.

Sequence: IPL, supervisor `LNS`, empty date, then on
the console `C2 ` (ICAM READY) and `RV IMS ` (IMS READY).

IMS's demo transaction `DISP` takes `DISP CUSTFIL key`, with a five character
key. The customer file on `REL042` (loaded by the cataloged job `VSB028`) has,
among others: `BR8TL`, `TR2HS`, `WO9BL`, `YD1RA`, `LO2BR`, `LO2SC`, `PE1PS`,
`CA1ES`, `CL3MD`, `RE1BA`, `RI4CL`, `RO1CS`.

## Changes to MAME

On top of the patch of [alfaskop-91](https://github.com/ajfa/alfaskop-91):

| file | change |
|---|---|
| `hd63450` | a transfer whose count runs out ends with COC only. MAME also set NDT and BTC (`E0`), and the SAS system stopped its boot on it with panel code `01`. The 3270 diskettes never look. |
| `z80sio` (MK68564) | XMTCTL bits 7 and 6 count 5, 6, 7 and 8 bits like RCVCTL; MAME sent 6 bits when the A91 asked for 7. |
| `a91` | the DCD pulse after a DU frame is skipped while the DU runs its IPL PROM, which took it as the end of a program block and fell back to a 63-byte window, looping on `LOAD P`/`LOAD I`. |
| `a91` | line 2: when channel B is set up for bisync, the host socket carries that line instead of X.21: a 19200 bit/s clock, constant DCD and CTS, 7-bit characters without parity and SYN fill on the socket. |
| `a91` | the DU station setting and the per-channel station selects. |
| `a91` | two byte cells when port B bit 5 of the MIC PIA is set; national characters through the same table as the 3270 mode, field delimiters blank. |
| `alfaskop_s41_kb` | key 55 on keypad `/`. |

## Pitfalls

* Reading the DU's I/O page from Lua (`F000-F7FF`, and `FFE8-FFF9`) has side
  effects: reading the ACIA or TCC data registers takes the byte away from the
  DU. A full 64K memory dump every few seconds made host text vanish without a
  trace. `tools/memdump.lua` reads RAM only.
* `str.splitlines()` in Python also splits at `RS` (`1E`), which starts every
  console entry; `console.py` splits on newline only.
