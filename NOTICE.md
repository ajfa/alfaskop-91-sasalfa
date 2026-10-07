# Notices and third-party material

## MAME

The patches in `patches/` apply to MAME 0.288 after the patch of
[alfaskop-91](https://github.com/ajfa/alfaskop-91), and are licensed
BSD-3-Clause, the same as the files they modify.

`src/mame/ericsson/a91.cpp` is `license:BSD-3-Clause`. Its copyright holder is
**Mattis Lind**, who wrote the first version of the driver; alfaskop-91 and
this repository extend it. `src/mame/skeleton/alfaskop_s41_kb.cpp` is
`license:BSD-3-Clause` by **Joakim Larsson Edström**. The device files touched
by the fixes, `hd63450.cpp` and `z80sio.cpp`, keep their own copyright holders
and license.

MAME itself is available at https://github.com/mamedev/mame

## U9030

The Univac 90/30 emulator U9030, its OS/3, ICAM and IMS disks and its console
client are by **Steve Boyd**, https://github.com/sboydlns/univacemulators, and
keep their own terms. None of it is included here; `windows/setup-u9030.ps1`
copies what it needs from the user's own installation.

## Ericsson material

**No Ericsson firmware, ROM image, diskette image or documentation is included
in this repository.**

The Alfaskop 91 hardware, firmware and software, including the SAS diskettes
and the display unit program described in `docs/NOTES.md`, are the work of
Ericsson Information Systems AB. References to part numbers, addresses, tables
and observed behaviour are descriptions of a historical system, made for
interoperability and preservation.

The SAS diskette images used for this work were imaged by Poul-Henning Kamp.
To run the emulation you need the ROM set and the diskette images, obtained
separately.

## Sperry Univac documentation

The protocol notes refer to the Uniscope manuals UP-7779 (Uniscope 100
Communications Control Procedures) and UP-7807 (Uniscope Display Terminal
Programmer's Reference), which are not included.
