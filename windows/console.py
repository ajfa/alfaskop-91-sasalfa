#!/usr/bin/env python3
# console.py [script] - the 90/30 system console over its TCP port (9030), in place of U9030Console.exe
# Script lines: "wait <regex>" on the decoded console text, "attn" (Msg Wait), "send <text>" (Transmit),
# "sleep <s>", "log <text>", "exec <command>", "waitfile <path> <regex>" (environment variables expand in
# the path). Without a script it only logs. Everything goes to console.log.
import os, re, socket, subprocess, sys, time

STX, ETX, BEL, ESC, DC4 = 2, 3, 7, 0x1b, 0x14
HOST, PORT = '127.0.0.1', 9030
log = open('console.log', 'a', encoding='utf-8')

def out(s):
    log.write(s + '\n')
    log.flush()
    print(s, flush=True)

def shown(b):
    return ''.join(chr(c) if 32 <= c < 127 else '<%02X>' % c for c in b)

def connect():
    for _ in range(600):
        try:
            s = socket.create_connection((HOST, PORT), timeout=2)
            s.settimeout(0.2)
            return s
        except OSError:
            time.sleep(0.5)
    raise SystemExit('console port did not open')

class Console:
    def __init__(self):
        self.s = connect()
        self.buf = b''
        self.text = ''
        out('== console connected')

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            try:
                d = self.s.recv(4096)
            except socket.timeout:
                continue
            if not d:
                raise SystemExit('console closed')
            self.buf += d
            while True:
                a = self.buf.find(bytes([STX]))
                if a < 0:
                    self.buf = b''
                    break
                e = self.buf.find(bytes([ETX]), a)
                if e < 0:
                    self.buf = self.buf[a:]
                    break
                msg = self.buf[a + 1:e]
                self.buf = self.buf[e + 1:]
                out('<< ' + shown(msg))
                self.text += re.sub(r'[\x00-\x1f]', ' ', msg.decode('latin-1')) + '\n'

    def wait(self, pat, secs=600):
        end = time.time() + secs
        while time.time() < end:
            m = re.search(pat, self.text)
            if m:
                self.text = self.text[m.end():]
                return True
            self.pump(0.3)
        raise SystemExit('timeout waiting for ' + pat)

    def attn(self):
        out('>> <attn>')
        self.s.sendall(bytes([BEL, ETX]))

    def send(self, text):
        out('>> ' + text)
        self.s.sendall(bytes([STX]) + text.encode('latin-1') + bytes([ETX]))

def main():
    c = Console()
    # only newline ends a line: splitlines() would also cut at RS (1E), which starts every console entry
    steps = open(sys.argv[1], encoding='latin-1').read().split(chr(10)) if len(sys.argv) > 1 else []
    for line in steps:
        if not line.strip() or line.startswith('#'):
            continue
        op, _, arg = line.partition(' ')
        if op == 'wait':
            c.wait(arg)
        elif op == 'attn':
            c.attn()
        elif op == 'send':
            c.send(arg.encode('latin-1').decode('unicode_escape'))
        elif op == 'sleep':
            c.pump(float(arg))
        elif op == 'log':
            out('== ' + arg)
        elif op == 'exec':
            out('== exec ' + arg)
            subprocess.Popen(arg.split(), creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        elif op == 'waitfile':
            path, _, pat = arg.partition(' ')
            path = os.path.expandvars(path)
            if path.startswith('$'):
                out('== %s is not set, not waiting' % path)
                continue
            out('== waiting for %s in %s' % (pat, path))
            while True:
                try:
                    if re.search(pat, open(path, encoding='latin-1').read()):
                        break
                except OSError:
                    pass
                c.pump(1)
    out('== script done')
    # then take more commands, one per line, appended to console.cmd
    seen = 0
    while True:
        c.pump(0.5)
        try:
            lines = open('console.cmd', encoding='latin-1').read().split(chr(10))[:-1]
        except OSError:
            continue
        for line in lines[seen:]:
            op, _, arg = line.partition(' ')
            if op == 'attn':
                c.attn()
            elif op == 'send':
                c.send(arg.encode('latin-1').decode('unicode_escape'))
            elif op == 'quit':
                return
        seen = len(lines)

main()
