#!/usr/bin/env python3
"""The Z80 converter (USR 45062) must give exactly what tools/front.py gives."""
import os, sys, re
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..'); sys.path.insert(0, HERE)
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from rig import Spectrum
import front, gen
sym = gen.symbols(); code = open(os.path.join(ROOT, 'build', 'speech.bin'), 'rb').read()
s = Spectrum(os.path.join(REPO, 'build', 'opticos.rom')); s.frame(200); s.load(gen.ORG, code)
g = front.load_rules()
def z80(text):
    tb = sym['textbuf']; s.load(tb, text.encode('latin1') + b'\0')
    r = s.call(gen.ORG + 6, SP=0x6000, limit=200_000_000)
    n = r['BC']; out = list(s.block(sym['allbuf'], n + 1))
    assert out[-1] == 0xFF, out
    return out[:-1]
words = sys.argv[1:]
if not words:
    src = open('/usr/share/dict/words').read().split() if os.path.exists('/usr/share/dict/words') else []
    words = [w for w in src if w.isalpha()][::40] + ["Hello Nathan", "Optica Technology Design", "I am a ZX Spectrum",
             "The quick brown fox, jumps over the lazy dog.", "It's 2026 - what's new?", "  lots   of   spaces  ",
             "Shouldn't we?", "CHURCH cheese thing shoe", "ELY ING ER ES ED", "x", "", "...", "Wh", "Judge"]
bad = 0
for w in words:
    a, b = z80(w), front.to_allophones(w, g)
    if a != b:
        bad += 1
        if bad <= 15: print('DIFF %r\n  z80 %s\n  py  %s' % (w, ' '.join(front.NAMES[c] for c in a), ' '.join(front.NAMES[c] for c in b)))
print('%d texts, %d differ' % (len(words), bad))
sys.exit(1 if bad else 0)
