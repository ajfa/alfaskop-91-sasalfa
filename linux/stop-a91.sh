#!/bin/bash
# stop-a91.sh - stop the MAME and the bridge that run-a91.sh started, by their pid files, and wait until they are gone
cd "$(dirname "$0")/../run/live" 2>/dev/null || exit 0
pids=""
for f in mame.pid bridge.pid; do
	p=$(cat $f 2>/dev/null)
	[ -n "$p" ] && ps -o args= -p "$p" | grep -q "a91du\|sasalfa-bridge" && kill "$p" && pids="$pids $p"
done
# MAME takes a few seconds to close after the signal
for i in $(seq 1 15); do
	alive=""
	for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
	[ -z "$alive" ] && exit 0
	sleep 1
done
echo "still running:$alive"
exit 1
