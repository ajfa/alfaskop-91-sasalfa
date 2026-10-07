#!/bin/bash
# run-a91.sh [seconds] - the SAS A91 in MAME without a window, its SASALFA line on sasalfa-bridge.py, whose
# 90/30 side waits on port 37523 for relay.py (Windows) or for anything that connects it to U9030's port 9036.
#   A91_MAME     the a91 binary built with patches/ (default: a91 in the current directory)
#   A91_ROMS     MAME rompath with the a91 and keyboard ROMs (default: roms)
#   A91_SAS_SYS  SAS system diskette, IMD (50007035)
#   A91_SAS_EM   SAS emulation diskette, IMD (50007032)
#   TYPE, TYPEAT text to type on the DU, from home, once past TYPEAT emulated seconds
# Logs, snapshots and the working copies of the diskettes go to run/live in the repository.
R=$(cd "$(dirname "$0")/.." && pwd)
MAME=$(realpath "${A91_MAME:-./a91}")
ROMS=$(realpath "${A91_ROMS:-roms}")
: "${A91_SAS_SYS:?set A91_SAS_SYS to the SAS system diskette}" "${A91_SAS_EM:?set A91_SAS_EM to the SAS emulation diskette}"
L=$R/run/live
mkdir -p "$L"
cp "$A91_SAS_SYS" "$L/SYS.IMD"
cp "$A91_SAS_EM" "$L/EM.IMD"
cd "$L" || exit 1
chmod 644 SYS.IMD EM.IMD
rm -f bridge.log sas.txt
python3 "$R/bridge/sasalfa-bridge.py" --a91 37522 --host-listen 37523 --log bridge.log > bridge.out 2>&1 &
echo $! > bridge.pid
sleep 1
TYPE="${TYPE:-}" TYPEAT=${TYPEAT:-0} STATION=2 NEXT=$R/lua/sas-select.lua \
env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
	"$MAME" a91du -rompath "$ROMS" -flop1 SYS.IMD -flop2 EM.IMD -video none -sound none \
	-skip_gameinfo -seconds_to_run "${1:-1200}" -snapshot_directory "$L" \
	-bitb socket.127.0.0.1:37522 -autoboot_script "$R/lua/station.lua" > mame.out 2>&1 &
echo $! > mame.pid
wait "$(cat mame.pid)"
kill "$(cat bridge.pid)" 2>/dev/null
