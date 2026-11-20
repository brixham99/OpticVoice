#!/usr/bin/env python3
"""Build OpticOS Speech: tools/gen.py (tables + pasmo) -> build/speech.bin, then
speech.tap and speech.tzx. As for Dino Run, the tape holds what the OpticOS ROM
itself writes: speech.bas is typed into the ROM in the OpticOS test rig, the code
is put at 45056, and the ROM's own  SAVE "speech" AUTO start  and
SAVE "speechcode" CODE 45056,n  are recorded off the MIC signal and decoded.
Usage: python3 build.py  (needs pasmo, numpy, scipy, and an OpticOS checkout with
build/opticos.rom and the rig's libz80.so: set OPTICOS, default /workspace/opticos-repo)"""
import os, sys, struct, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, 'tools'))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
import gen
gen.generate(); ORG = gen.ORG
code = open(os.path.join(HERE, 'build', 'speech.bin'), 'rb').read()
sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from p3lib import Basic
from rig import decode_pulses
prog = [l.rstrip() for l in open(os.path.join(HERE, 'speech.bas')) if l.strip()]
b = Basic(); s = b.s
b.line('NEW'); b.enter([l.strip() for l in prog])
b.line('CLEAR %d' % (ORG - 1))      # BASIC's stacks must sit below the code
s.load(ORG, code)
def record(cmd, name, typ):
    s.mic_start(3); b.line(cmd, 3_000_000_000)
    got = decode_pulses(s.mic_pulses())
    assert len(got) == 2, (name, len(got))
    hdr, data = got
    assert hdr[0] == 0 and hdr[1] == typ and len(hdr) == 19 and hdr[2:12].decode().rstrip() == name, hdr
    for blk in got:
        p = 0
        for x in blk[:-1]: p ^= x
        assert p == blk[-1], name
    return [bytes(hdr), bytes(data)]
blocks = record('SAVE "speech" AUTO start', 'speech', 0)
assert blocks[1][1:5] == b'OB\x01\x00', 'not an OpticBASIC program'
blocks += record('SAVE "speechcode" CODE %d,%d' % (ORG, len(code)), 'speechcode', 3)
assert blocks[3][1:-1] == code and blocks[2][14] | blocks[2][15] << 8 == ORG
tap = b''.join(struct.pack('<H', len(x)) + x for x in blocks)
open(os.path.join(HERE, 'speech.tap'), 'wb').write(tap)
tzx = b'ZXTape!\x1a\x01\x14' + b''.join(b'\x10' + struct.pack('<HH', 1000, len(x)) + x for x in blocks)
open(os.path.join(HERE, 'speech.tzx'), 'wb').write(tzx)
print('program speech: %d bytes; speechcode: CODE %d,%d (ends %d); buffers to %d' % (
    len(blocks[1]) - 2, ORG, len(code), ORG + len(code) - 1, gen.symbols()['bufend'] - 1))
print('wrote speech.tap (%d bytes) and speech.tzx (%d bytes)' % (len(tap), len(tzx)))
