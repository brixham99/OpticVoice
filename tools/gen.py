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

OS_SYMS = ['boot', 'ext_back', 'id_skip', 'ev_expr', 'ev_pop', 'ev_int', 'err_type', 'err_syn', 'err_arg', 'err_nomem', 'LD_BYTES', 'T_LOAD']
EXT_AYTAB = 0x3D00
def ext_source(src):
    """the 128K speech code as an OpticOS 128 extension ROM (slot 1): the RAM header goes, the
    variables become equates in the workspace, ext128_main.asm leads, OpticOS addresses from its .sym"""
    import re
    os_sym = {}
    # the OpticOS build with the extension hook (branch opticos128-say): OPTICOS128_SYM, else OPTICOS/build
    for l in open(os.environ.get('OPTICOS128_SYM') or os.path.join(os.environ.get('OPTICOS', '/workspace/opticos-repo'), 'build', 'opticos.sym')):
        p = l.split()
        if len(p) >= 3 and p[1] == 'EQU': os_sym[p[0]] = int(p[2].rstrip('H'), 16)
    head = ''.join('OS_%s equ $%04X\n' % (k, os_sym[k]) for k in OS_SYMS) + 'OS_ERR_TAPE equ $1A\n'
    a, b = src.index(';@ORG'), src.index('say_text:')
    src = src[:a] + open(os.path.join(ROOT, 'src', 'ext128_main.asm')).read() + '\n' + src[b:]
    out, off, invars = [], 0, False
    for l in src.split('\n'):
        if l.startswith('sfx:'): invars = True
        if l.startswith('codeend:'): invars = 'end'
        m = re.match(r'^(\w+):\s+(dw|db) 0\s*$', l) if invars is True else None
        if m: out.append('%s equ WVARS+%d' % (m.group(1), off)); off += 2 if m.group(2) == 'dw' else 1; continue
        if invars == 'end' and re.match(r'^(textbuf|wbuf0|wbuf|allbuf|bufend)\s+equ', l): continue
        out.append(l)
    assert off <= 192 - 64, off
    return head + '\n'.join(out)
def generate(m128=False, ext=False, org=None, name=None):
    """org/name: another 48K build, e.g. org=46080, name='speech48rom' for the standard 48K ROM"""
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
    if ext: src = ext_source(src)
    gen = (['; ---- generated by tools/gen.py: do not edit', 'BITLOOP macro', 'endm'] if False else [])
    src = src.replace('        jr ', '        jp ')         # range; the timed code is generated below
    src = src.replace(';@BITS', '\n'.join(bits)).replace(';@PADBITS', '\n'.join(pbits))
    src = src.replace(';@AYBITS', '\n'.join(aysample(True))).replace(';@AYPADBITS', '\n'.join(aysample(False))).replace(';@ORG', '        org %d' % (ORG128 if m128 else org or ORG))
    tail = (['; ---- tables generated by tools/gen.py'] + ['gindex:'] + gidx + db('lflags', flags) +
            db('ctab', front.CTAB) + db('vtab', front.VTAB) +
            db('rules', list(rules)))
    banks = []
    if m128:
        bb, db_ = banks_for(F, synth.NBYTE, list(BEEP_BANKS), 0); ab, da = banks_for(synth.build_frames_ay(), synth.PERIOD_AY, list(AY_BANKS), 1)
        banks = bb + ab
        tail += ['dirb:'] + ['        db %d\n        dw %d' % d for d in db_] + ['dira:'] + ['        db %d\n        dw %d' % d for d in da]
        aytail = ['        org %d' % (EXT_AYTAB if ext else AYTAB), 'aytab:'] + sum((db(None, list(synth.AY_TRI[:, k])) for k in range(3)), [])
    else:
        tail += ['allotab:'] + ['        dw allo+%d' % t for t in tab] + db('allo', blob) + ['dirb    equ allotab', 'dira    equ allotab']
        aytail = []
    src = src.replace(';@TABLES', '\n'.join(tail)) + '\n' + '\n'.join(aytail) + '\n'
    name = name or ('ext128' if ext else 'speech128' if m128 else 'speech')
    open(os.path.join(ROOT, 'src', name + '.asm'), 'w').write(src)
    os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
    subprocess.run([PASMO, '--bin', 'src/%s.asm' % name, 'build/%s.bin' % name, 'build/%s.sym' % name], cwd=ROOT, check=True)
    for b, img in banks: open(os.path.join(ROOT, 'build', 'bank%d.bin' % b), 'wb').write(bytes(img))
    if ext:
        sy = symbols(name); assert sy['codeend'] <= EXT_AYTAB and sy['bufend'] <= 0xC000, (hex(sy['codeend']), hex(sy['bufend']))
        rom = open(os.path.join(ROOT, 'build', 'ext128.bin'), 'rb').read(); assert len(rom) <= 16384, len(rom)
        open(os.path.join(ROOT, 'build', 'opticos128ext.rom'), 'wb').write(rom + bytes(16384 - len(rom)))
    elif m128:
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
    generate(True, True); s = symbols('ext128')
    print('extension ROM (slot 1): code $%04X-$%04X, aytab $%04X-$3FFF; RAM workspace $BA00-$%04X' % (
        s['ext_main'], s['codeend'] - 1, EXT_AYTAB, s['bufend'] - 1))
