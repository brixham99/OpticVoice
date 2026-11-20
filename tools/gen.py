#!/usr/bin/env python3
"""Generate src/speech.asm (player with cycle-exact bit timing, text converter,
rule and allophone tables) and assemble it with pasmo to build/speech.bin."""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..'); sys.path.insert(0, HERE)
import numpy as np, front, synth
PASMO = os.environ.get('PASMO', '/workspace/tools-prefix/usr/bin/pasmo')
ORG = 45056                     # CLEAR 45055 (48K build)
ORG128 = 38912                  # CLEAR 38911 (128K build: resident $9800-$BFFF)
AYTAB = 0xBD00                  # 128K: AY volume table, 3 pages up to $BFFF
BEEP_BANKS = [4]                # 128K: banks for the beeper data (uncontended)
AY_BANKS = [6, 1, 3, 7]         # 128K: banks for the AY data, uncontended 6 first
BANK_HDR = 8 + 128              # 'SPKD', version, device, bank, count, then 64 x dw address
_n = [0]
def pad(t):
    """instructions taking exactly t T-states (A is free)"""
    for N in range((t - 2) // 16, -1, -1):
        r = t - (16 * N + 2) if N else t
        for b in range(r // 7 + 1):
            if (r - 7 * b) % 4 == 0:
                _n[0] += 1; out = []
                if N: out += ['        ld a,%d' % N, 'pd%d:    dec a' % _n[0], '        jr nz,pd%d' % _n[0]]
                out += ['        ld a,0'] * b + ['        nop'] * ((r - 7 * b) // 4)
                return out
    raise ValueError(t)
def bitcode(last, loop='bloop', load=13):
    """one output bit, exactly 112 T including (for the last bit of a byte) the loop
    jump and the next byte's load (ld e,(hl) / inc hl = 13 T; ld e,n = 7 T)"""
    c = ['        rl e', '        sbc a,a', '        and 16', '        or b', '        out ($FE),a']   # 34 T
    if not last: return c + pad(112 - 34)
    return c + pad(112 - 34 - 14 - load) + ['        dec d', '        jp nz,' + loop]
def aysample(load):
    """one AY sample, exactly 259 T including the loop: three volume writes from aytab"""
    c = ['        ld e,(hl)', '        inc hl'] if load else ['        ld e,AYPAD']
    for r in (8, 9, 10):
        c += ['        ld b,$FF', '        ld a,%d' % r, '        out (c),a', '        ld b,$BF', '        ld a,(de)',
              '        out (c),a'] + (['        inc d'] if r < 10 else ['        dec d', '        dec d'])
    t = (13 if load else 7) + 3 * 52 + 16 + 40
    return c + pad(259 - t + 0) + ['        ld a,(cnt)', '        dec a', '        ld (cnt),a',
                                   '        jp nz,' + ('ays_lp' if load else 'ayp_lp')]
def db(label, data):
    out = [label + ':'] if label else []
    for i in range(0, len(data), 16): out.append('        db ' + ','.join(str(x) for x in data[i:i + 16]))
    return out

def blob_of(fr, nbytes):
    blob = []
    for rep, bits, voiced in fr:
        if bits is None:
            while rep: k = min(rep, 127); blob.append(0x80 | k); rep -= k
        else:
            assert 1 <= rep <= 63
            blob.append(rep | (0x40 if voiced else 0)); blob += list(np.packbits(bits) if nbytes == synth.NBYTE else bits)
    return blob + [0]
def banks_for(F, nbytes, banks, device):
    """pack the allophones into 16K banks: [(bank, image)], directory [(bank, address)] x 64"""
    out, dirs = [], [None] * 64; cur = None
    for i, name in enumerate(front.NAMES):
        b = blob_of(F[name], nbytes)
        if cur is None or len(cur[1]) + len(b) > 16384:
            assert banks, 'out of banks'
            cur = (banks.pop(0), bytearray(b'SPKD' + bytes([3, device, 0, 0]) + bytes(128))); cur[1][6] = cur[0]; out.append(cur)
        addr = 0xC000 + len(cur[1]); cur[1].extend(b); dirs[i] = (cur[0], addr)
        cur[1][7] += 1; cur[1][8 + 2 * i] = addr & 255; cur[1][9 + 2 * i] = addr >> 8
    return out, dirs
def allophone_data():
    F = synth.build_frames(); tab, blob = [], []
    for name in front.NAMES:
        tab.append(len(blob)); fr = F[name]
        for rep, bits, voiced in fr:
            if bits is None:
                while rep: k = min(rep, 127); blob.append(0x80 | k); rep -= k
            else:
                assert 1 <= rep <= 63
                blob.append(rep | (0x40 if voiced else 0)); blob += list(np.packbits(bits))
        blob.append(0)
    return F, tab, blob

def generate(m128=False):
    groups = front.load_rules(); index, rules = front.encode(groups)
    F, tab, blob = allophone_data()
    gidx = ['        dw %s' % ('rules+%d' % index[chr(c)] if chr(c) in index else '0') for c in range(32, 96)]
    flags = []
    for ch in range(26):
        c = chr(65 + ch); f = 0
        if c in front.VOWELS: f |= 1
        if c in front.CONS: f |= 2
        if c in front.VOICED: f |= 4
        if c in front.FRONT: f |= 8
        if c in 'SCGZXJ': f |= 16
        if c in 'TSRDLZNJ': f |= 32
        flags.append(f)
    src = open(os.path.join(ROOT, 'src', 'speech_main.asm')).read()
    bits, pbits = [], []
    for k in range(8): bits += bitcode(k == 7); pbits += bitcode(k == 7, 'ploop', 7)
    src = 'M128    equ %d\nAYPAD   equ %d\n' % (int(m128), synth.AY_PAD) + src
    gen = (['; ---- generated by tools/gen.py: do not edit', 'BITLOOP macro', 'endm'] if False else [])
    src = src.replace('        jr ', '        jp ')         # range; the timed code is generated below
    src = src.replace(';@BITS', '\n'.join(bits)).replace(';@PADBITS', '\n'.join(pbits))
    src = src.replace(';@AYBITS', '\n'.join(aysample(True))).replace(';@AYPADBITS', '\n'.join(aysample(False))).replace(';@ORG', '        org %d' % (ORG128 if m128 else ORG))
    tail = (['; ---- tables generated by tools/gen.py'] + ['gindex:'] + gidx + db('lflags', flags) +
            db('ctab', front.CTAB) + db('vtab', front.VTAB) +
            db('rules', list(rules)))
    banks = []
    if m128:
        bb, db_ = banks_for(F, synth.NBYTE, list(BEEP_BANKS), 0); ab, da = banks_for(synth.build_frames_ay(), synth.PERIOD_AY, list(AY_BANKS), 1)
        banks = bb + ab
        tail += ['dirb:'] + ['        db %d\n        dw %d' % d for d in db_] + ['dira:'] + ['        db %d\n        dw %d' % d for d in da]
        aytail = ['        org %d' % AYTAB, 'aytab:'] + sum((db(None, list(synth.AY_TRI[:, k])) for k in range(3)), [])
    else:
        tail += ['allotab:'] + ['        dw allo+%d' % t for t in tab] + db('allo', blob) + ['dirb    equ allotab', 'dira    equ allotab']
        aytail = []
    src = src.replace(';@TABLES', '\n'.join(tail)) + '\n' + '\n'.join(aytail) + '\n'
    name = 'speech128' if m128 else 'speech'
    open(os.path.join(ROOT, 'src', name + '.asm'), 'w').write(src)
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    subprocess.run([PASMO, '--bin', 'src/%s.asm' % name, 'build/%s.bin' % name, 'build/%s.sym' % name], cwd=ROOT, check=True)
    for b, img in banks: open(os.path.join(ROOT, 'build', 'bank%d.bin' % b), 'wb').write(bytes(img))
    if m128:
        sy = symbols(name); assert sy['bufend'] <= AYTAB, hex(sy['bufend'])
    return F, len(rules), len(blob), banks
def _unused():
    open(os.path.join(ROOT, 'src', 'speech.asm'), 'w').write(src)
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    subprocess.run([PASMO, '--bin', 'src/speech.asm', 'build/speech.bin', 'build/speech.sym'], cwd=ROOT, check=True)
    return F, len(rules), len(blob)

def symbols(name='speech'):
    d = {}
    for l in open(os.path.join(ROOT, 'build', name + '.sym')):
        p = l.split()
        if len(p) >= 3 and p[1] == 'EQU': d[p[0]] = int(p[2].rstrip('H'), 16)
    return d

if __name__ == '__main__':
    F, nr, na, _ = generate(); s = symbols(); code = open(os.path.join(ROOT, 'build', 'speech.bin'), 'rb').read()
    print('48K: rules %d bytes, allophones %d bytes (+128 table), code block %d..%d = %d bytes; buffers end %d' % (
        nr, na, ORG, ORG + len(code) - 1, len(code), s['bufend'] - 1))
    F, nr, na, banks = generate(True); s = symbols('speech128'); code = open(os.path.join(ROOT, 'build', 'speech128.bin'), 'rb').read()
    print('128K: resident %d..%d = %d bytes (code+tables to %d, buffers to %d, aytab %d..%d); banks: %s' % (
        ORG128, ORG128 + len(code) - 1, len(code), s['codeend'] - 1, s['bufend'] - 1, AYTAB, AYTAB + 767,
        ', '.join('%d: %d bytes (%d allophones, device %d)' % (b, len(img), img[7], img[5]) for b, img in banks)))
