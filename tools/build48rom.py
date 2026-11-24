"""build48rom.py - OpticVoice for the standard Sinclair 48K ROM: opticvoice48rom.tap/.tzx
(program "opticvoice" LINE 20, then CODE "ovcode48" 46080,18231)."""
import os, sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(HERE, 'tools'))
import gen, zxbasic
ORG = 46080
gen.generate(org=ORG, name='speech48rom'); s = gen.symbols('speech48rom')
code = open(os.path.join(HERE, 'build', 'speech48rom.bin'), 'rb').read()
assert s['bufend'] <= 65368, s['bufend']          # the UDGs (65368-65535) stay untouched
prog = zxbasic.program(open(os.path.join(HERE, 'opticvoice48rom.bas')).read())
zxbasic.write(os.path.join(HERE, 'opticvoice48rom'), [
    zxbasic.header(0, 'opticvoice', len(prog), 20, len(prog)), zxbasic.block(255, prog),
    zxbasic.header(3, 'ovcode48', len(code), ORG, 32768), zxbasic.block(255, code)])
print('opticvoice48rom: program %d bytes; CODE %d,%d (to %d); buffers %d-%d; free to UDGs %d-65367' % (
    len(prog), ORG, len(code), ORG + len(code) - 1, s['textbuf'], s['bufend'] - 1, s['bufend']))
