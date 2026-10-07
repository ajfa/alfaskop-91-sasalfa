#!/usr/bin/env python3
"""fakehost.py PORT READYFILE [CTRLS] - stand in for the U9030 line adapter on sasalfa-bridge.py's --host-listen
port. Once READYFILE holds two 'snapshot' lines (sas-select.lua's log), send one screen with a row per control
character, "cc ab" + control + "cdefgh", so the DU video RAM shows what each one does to the attributes."""
import socket, sys, time

port, ready = int(sys.argv[1]), sys.argv[2]
ctrls = [int(x, 16) for x in (sys.argv[3] if len(sys.argv) > 3 else '41').split()]
text = b'\x02\x1b\x0b  \x0f\x1ba'
for i, c in enumerate(ctrls):
    text += b'\x1b\x0b' + bytes([0x21 + i, 0x20]) + b'\x0f' + b'%02X ab' % c + bytes([c]) + b'cdefgh'
text += b'\x03'
s = socket.create_connection(('127.0.0.1', port))
s.sendall(b'\xff\x20\xff\xff\x22\x51')
while True:
    try:
        if open(ready).read().count('snapshot') >= 2:
            break
    except OSError:
        pass
    time.sleep(1)
s.sendall(text)
print('sent', text.hex(' '), flush=True)
s.settimeout(1)
while True:
    try:
        d = s.recv(4096)
        if not d:
            break
        print('from A91', d.hex(' '), flush=True)
    except socket.timeout:
        pass
