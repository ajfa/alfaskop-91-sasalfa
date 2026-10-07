#!/bin/bash
# stop-a91.sh - stop the MAME and the bridge that run-a91.sh started, by their pid files
cd "$(dirname "$0")/../run/live" 2>/dev/null || exit 0
for f in mame.pid bridge.pid; do
	p=$(cat $f 2>/dev/null)
	[ -n "$p" ] && ps -o args= -p "$p" | grep -q "a91du\|sasalfa-bridge" && kill "$p"
done
true
