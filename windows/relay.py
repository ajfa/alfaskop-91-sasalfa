#!/usr/bin/env python3
# relay.py A_HOST:PORT B_HOST:PORT - join two TCP servers byte for byte (used to reach a bridge running in WSL)
import select, socket, sys, time

def connect(spec):
    h, p = spec.rsplit(':', 1)
    for _ in range(1200):
        try:
            return socket.create_connection((h, int(p)))
        except OSError:
            time.sleep(0.5)
    raise SystemExit('could not reach ' + spec)

a = connect(sys.argv[1])
b = connect(sys.argv[2])
peer = {a: b, b: a}
while True:
    r, _, _ = select.select([a, b], [], [])
    for s in r:
        d = s.recv(4096)
        if not d:
            sys.exit(0)
        peer[s].sendall(d)
