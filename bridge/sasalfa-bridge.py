#!/usr/bin/env python3
"""sasalfa-bridge.py - put an emulated Alfaskop 91 on a Univac 90/30's ICAM line.

The A91 side is the MAME driver's line 2 socket: 7-bit characters of a Uniscope-style
(SASALFA) poll/select line, without SYN fill or parity. Towards the A91 the bridge is the
host: it polls the terminal, takes its text, acknowledges it and selects it with the host's
output. The 90/30 side is the U9030 emulator's line adapter port (9036 for IMS, 9034 for BEM),
where the adapter itself answers ICAM's polls and only text crosses the TCP connection.

  sasalfa-bridge.py [--a91 PORT] [--host HOST:PORT | --host-listen PORT] [--log FILE]

--a91 is the port MAME's bitbanger connects to (-bitb socket.127.0.0.1:PORT). --host connects
to the U9030 line port; --host-listen instead waits for something that forwards it.
"""
import argparse, select, socket, sys, time

SOH, STX, ETX, EOT, ENQ, BEL, DLE, NAK, SYN = 0x01, 0x02, 0x03, 0x04, 0x05, 0x07, 0x10, 0x15, 0x16
ACK_WAIT = 1.0  # resend host text not acknowledged by then
RID, SID, DID = 0x22, 0x51, 0x70  # the SAS configuration's RID, its first sub-station, no device
# text to DID 70 goes to the message line; the screen of the DU at station 2 is DID 72 (C9B/ADDRESS)
TEXT_DID = 0x72
POLL_EVERY = 0.1
REPLY_WAIT = 2.0

def bcc(body):
    x = 0
    for c in body:
        x ^= c
    return x

def frame(body):
    # the A91 hunts for SYN SYN again after every message, so each one carries its own
    body = bytes(body)
    return bytes([SYN] * 4 + [SOH]) + body + bytes([bcc(body)])

def shown(b):
    return ''.join(chr(c) if 32 <= c < 127 else '<%02X>' % c for c in b)

class Bridge:
    def __init__(self, a, h, logf):
        self.a, self.h, self.logf = a, h, logf
        self.t0 = time.time()
        self.arx = b''
        self.hrx = b''
        self.host_out = []    # text from the 90/30 waiting for the A91
        self.waiting = None   # what we sent and are waiting a reply to
        self.sent_at = 0
        self.ack_due = False  # the A91's last text needs acknowledging
        self.unacked = None   # host text the A91 has not acknowledged yet: [text, sent at, tries]
        self.next_poll = 0

    def log(self, s):
        line = '%9.3f %s' % (time.time() - self.t0, s)
        self.logf.write(line + '\n')
        self.logf.flush()

    def to_a91(self, body, what, text=None):
        f = frame(body)
        self.a.sendall(f)
        self.waiting, self.sent_at, self.sent_text = what, time.time(), text
        if what != 'poll':
            self.log('HOST>A91 %s %s' % (what, shown(f)))

    def a91_message(self):
        """take one complete message from the A91 buffer: up to ETX and its BCC"""
        while self.arx[:1] == b'\x7f':
            self.arx = self.arx[1:]
        e = self.arx.find(bytes([ETX]))
        if e < 0 or len(self.arx) < e + 2:
            return None
        m, self.arx = self.arx[:e + 2], self.arx[e + 2:]
        return m

    def from_a91(self, m):
        body = m[1:-1] if m[0] == SOH else m[:-1]
        if bcc(body) != m[-1]:
            self.log('A91 bad BCC %s' % shown(m))
            return
        was, self.waiting = self.waiting, None
        if m[0] == EOT:
            if was not in (None, 'poll'):
                self.log('A91 EOT to the %s' % was)
            return
        if m[0] != SOH or len(m) < 6:
            self.log('A91 ? %s' % shown(m))
            return
        rid, sid, did = m[1], m[2], m[3]
        rest = m[4:-2]
        if rest[:1] == bytes([STX]):
            self.log('A91 text rid=%02X sid=%02X did=%02X %s' % (rid, sid, did, shown(rest)))
            # the A91 opens with ESC VT row col 'B' SI; a UTS 400/U200 sends NUL in that place, and IMS
            # does not find the transaction code otherwise
            if rest[1:3] == b'\x1b\x0b' and rest[6:7] == b'\x0f':
                rest = rest[:5] + b'\x00' + rest[6:]
            self.h.sendall(rest + bytes([ETX]))
            self.ack_due = True
            self.unacked = None
        elif rest[:2] == bytes([DLE, 0x31]):
            # an acknowledgement without traffic is itself acknowledged with the next poll (UP-7779, rule 4)
            self.log('A91 ack')
            self.unacked = None
            self.ack_due = True
        elif rest[:2] == bytes([DLE, ENQ]):
            # reply request: our acknowledgement went missing, repeat it with a specific poll (rule 9)
            self.log('A91 reply request')
            self.ack_due = True
        elif rest[:1] == bytes([BEL]):
            self.log('A91 message waiting')
        else:
            self.log('A91 other %s' % shown(m))

    def from_host(self):
        # the adapter opens with a fake telnet command and then IAC IAC RID SID
        while True:
            while self.hrx[:1] == b'\xff':
                n = 4 if self.hrx[1:2] == b'\xff' else 2
                if len(self.hrx) < n:
                    return
                if n == 4:
                    self.log('U9030 gave us RID %02X SID %02X' % (self.hrx[2], self.hrx[3]))
                self.hrx = self.hrx[n:]
            s = self.hrx.find(bytes([STX]))
            b = self.hrx.find(bytes([BEL]))
            starts = [x for x in (s, b) if x >= 0]
            if not starts:
                self.hrx = self.hrx[-1:] if self.hrx[-1:] == b'\xff' else b''
                return
            a = min(starts)
            e = self.hrx.find(bytes([ETX]), a)
            if e < 0:
                self.hrx = self.hrx[a:]
                return
            text, self.hrx = self.hrx[a:e], self.hrx[e + 1:]
            self.log('U9030 %s' % shown(text))
            self.host_out.append(text)

    def step(self):
        # Uniscope: the terminal does not answer host text; it acknowledges it (DLE 1) when next polled
        now = time.time()
        if self.waiting and now - self.sent_at > REPLY_WAIT:
            self.log('A91 did not answer the %s' % self.waiting)
            self.waiting = None
        if self.waiting:
            return
        if self.unacked and now - self.unacked[1] > ACK_WAIT:
            if self.unacked[2] >= 5:
                self.log('A91 never acknowledged, dropped')
                self.unacked = None
            else:
                self.host_out.insert(0, self.unacked[0])
                self.unacked[2] += 1
        if self.ack_due:
            # a poll with acknowledge comes before any new text to the station (rules 5 and 7)
            self.ack_due = False
            self.to_a91(bytes([RID, SID, DID, DLE, 0x31, ETX]), 'ack poll')
            return
        if self.host_out and (not self.unacked or self.host_out[0] is self.unacked[0]):
            t = self.host_out.pop(0)
            tries = self.unacked[2] if self.unacked else 0
            self.to_a91(bytes([RID, SID, TEXT_DID]) + t + bytes([ETX]), 'text')
            self.unacked = [t, now, tries]
            self.waiting = None
        if self.unacked or now >= self.next_poll:
            self.next_poll = now + POLL_EVERY
            self.to_a91(bytes([RID, SID, DID, ETX]), 'poll')

    def run(self, a91_listener):
        while True:
            r, _, _ = select.select([self.a, self.h], [], [], 0.02)
            for s in r:
                d = s.recv(4096)
                if not d:
                    if s is self.h:
                        self.log('U9030 closed')
                        return
                    # a restarted MAME connects again; the 90/30 keeps its terminal meanwhile
                    self.log('A91 closed, waiting for it again')
                    self.a.close()
                    self.a, _ = a91_listener.accept()
                    self.arx, self.waiting, self.ack_due = b'', None, False
                    self.log('A91 connected')
                    break
                if s is self.a:
                    self.arx += d
                    while True:
                        m = self.a91_message()
                        if m is None:
                            break
                        self.from_a91(m)
                else:
                    self.hrx += d
                    self.from_host()
            self.step()

def listener(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(1)
    return s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--a91', type=int, default=37522)
    ap.add_argument('--host', default='127.0.0.1:9036')
    ap.add_argument('--host-listen', type=int)
    ap.add_argument('--rid', type=lambda v: int(v, 16), default=0x22,
                    help='the A91 answers broadcast polls, but takes text only at its own RID (hex)')
    ap.add_argument('--log', default='bridge.log')
    o = ap.parse_args()
    global RID
    RID = o.rid
    logf = open(o.log, 'a', encoding='utf-8')
    al = listener(o.a91)
    a, _ = al.accept()
    logf.write('A91 connected\n'); logf.flush()
    if o.host_listen:
        hl = listener(o.host_listen)
        h, _ = hl.accept()
        hl.close()
    else:
        hh, hp = o.host.rsplit(':', 1)
        h = socket.create_connection((hh, int(hp)))
    logf.write('90/30 line connected\n'); logf.flush()
    Bridge(a, h, logf).run(al)

main()
