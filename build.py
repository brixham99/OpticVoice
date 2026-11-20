#!/usr/bin/env python3
"""Build OpticOS Speech: tools/gen.py (tables + pasmo) -> build/speech.bin, then
speech.tap and speech.tzx. As for Dino Run, the tape holds what the OpticOS ROM
itself writes: speech.bas is typed into the ROM in the OpticOS test rig, the code
is put at 45056, and the ROM's own  SAVE "speech" AUTO start  and
SAVE "speechcode" CODE 45056,n  are recorded off the MIC signal and decoded.
Also builds speech128.tap/.tzx for a 128K (resident code + banks 4, 6, 1, 3).
Usage: python3 build.py  (needs pasmo, numpy, scipy, and an OpticOS checkout with
build/opticos.rom and the rig's libz80.so: set OPTICOS, default /workspace/opticos-repo)"""
import os, sys, struct, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, 'tools'))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
import gen
sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from p3lib import Basic
from rig import decode_pulses
def record(b, cmd, name, typ):
    s = b.s; s.mic_start(3); b.line(cmd, 3_000_000_000)
    got = decode_pulses(s.mic_pulses())
    assert len(got) == 2, (name, len(got))
    hdr, data = got
    assert hdr[0] == 0 and hdr[1] == typ and len(hdr) == 19 and hdr[2:12].decode().rstrip() == name, hdr
    for blk in got:
        p = 0
        for x in blk[:-1]: p ^= x
        assert p == blk[-1], name
    return [bytes(hdr), bytes(data)]
def tape(m128):
    """speech.tap/.tzx (48K) or speech128.tap/.tzx (128K: program, resident code, banks 4, 6, 1, 3)"""
    _, _, _, banks = gen.generate(m128); ORG = gen.ORG128 if m128 else gen.ORG
    name, cname, bas = ('speech128', 'sp128code', 'speech128.bas') if m128 else ('speech', 'speechcode', 'speech.bas')
    code = open(os.path.join(HERE, 'build', name + '.bin'), 'rb').read()
    prog = [l.rstrip() for l in open(os.path.join(HERE, bas)) if l.strip()]
    b = Basic(); s = b.s
    b.line('NEW'); b.enter([l.strip() for l in prog])
    b.line('CLEAR %d' % (ORG - 1))      # BASIC's stacks must sit below the code
    s.load(ORG, code)
    blocks = record(b, 'SAVE "%s" AUTO start' % name, name, 0)
    assert blocks[1][1:5] == b'OB\x01\x00', 'not an OpticBASIC program'
    blocks += record(b, 'SAVE "%s" CODE %d,%d' % (cname, ORG, len(code)), cname, 3)
    assert blocks[3][1:-1] == code and blocks[2][14] | blocks[2][15] << 8 == ORG
    for bank, img in banks:              # the rig is flat 64K: put each bank's image at $C000 and SAVE it
        s.load(0xC000, bytes(img)); blocks += record(b, 'SAVE "bank%d" CODE 49152,%d' % (bank, len(img)), 'bank%d' % bank, 3)
        assert blocks[-1][1:-1] == bytes(img)
    tap = b''.join(struct.pack('<H', len(x)) + x for x in blocks)
    open(os.path.join(HERE, name + '.tap'), 'wb').write(tap)
    tzx = b'ZXTape!\x1a\x01\x14' + b''.join(b'\x10' + struct.pack('<HH', 1000, len(x)) + x for x in blocks)
    open(os.path.join(HERE, name + '.tzx'), 'wb').write(tzx)
    print('program %s: %d bytes; %s: CODE %d,%d (ends %d); buffers to %d%s' % (
        name, len(blocks[1]) - 2, cname, ORG, len(code), ORG + len(code) - 1, gen.symbols(name)['bufend'] - 1,
        ''.join('; bank%d CODE 49152,%d' % (bk, len(im)) for bk, im in banks)))
    print('wrote %s.tap (%d bytes) and %s.tzx (%d bytes)' % (name, len(tap), name, len(tzx)))
def tape_ext():
    """say128.tap/.tzx for OpticOS 128 (the SAY extension ROM): the program and banks 4, 6, 1, 3"""
    _, _, _, banks = gen.generate(True)
    prog = [l.rstrip() for l in open(os.path.join(HERE, 'say128.bas')) if l.strip()]
    b = Basic(); s = b.s
    b.line('NEW'); b.enter([l.strip() for l in prog])
    blocks = record(b, 'SAVE "say128" AUTO start', 'say128', 0)
    for bank, img in banks:
        s.load(0xC000, bytes(img)); blocks += record(b, 'SAVE "bank%d" CODE 49152,%d' % (bank, len(img)), 'bank%d' % bank, 3)
    tap = b''.join(struct.pack('<H', len(x)) + x for x in blocks)
    open(os.path.join(HERE, 'say128.tap'), 'wb').write(tap)
    open(os.path.join(HERE, 'say128.tzx'), 'wb').write(b'ZXTape!\x1a\x01\x14' + b''.join(b'\x10' + struct.pack('<HH', 1000, len(x)) + x for x in blocks))
    print('wrote say128.tap/.tzx: program %d bytes + banks %s' % (len(blocks[1]) - 2, ', '.join(str(b) for b, _ in banks)))
    gen.generate(True, True)
tape(False); tape(True); tape_ext()
