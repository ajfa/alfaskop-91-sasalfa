#!/bin/bash
# stop-a91.sh - stop the MAME and the bridge that run-a91.sh started, by their pid files, and wait until they are gone.
# MAME without a window does not act on SIGTERM, so it gets SIGKILL after five seconds; it works on copies of the disks.
cd "$(dirname "$0")/../run/live" 2>/dev/null || exit 0
pids=""
for f in mame.pid bridge.pid; do
	p=$(cat $f 2>/dev/null)
	[ -n "$p" ] && ps -o args= -p "$p" | grep -q "a91du\|sasalfa-bridge" && kill "$p" 2>/dev/null && pids="$pids $p"
done
for i in $(seq 1 10); do
	alive=""
	for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
	[ -z "$alive" ] && exit 0
	sleep 0.5
done
kill -9 $alive 2>/dev/null
sleep 1
for p in $alive; do kill -0 "$p" 2>/dev/null && { echo "still running: $p"; exit 1; }; done
exit 0
