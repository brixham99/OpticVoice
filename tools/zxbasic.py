"""zxbasic.py - tokenise a Sinclair BASIC listing (line numbers, keywords in capitals) into a
48K program image and write .tap/.tzx files.  Keyword codes 165-255 are the published
ZX Spectrum character set (BASIC manual, appendix A); no ROM is read.

Rules for the source: keywords in CAPITALS, variables in lower case; spaces outside
strings and REMs are dropped (Sinclair BASIC ignores them); numbers get the hidden 5-byte
form (integers -65535..65535 only, which is all this program needs)."""
import struct
KW = ('RND INKEY$ PI FN POINT SCREEN$ ATTR AT TAB VAL$ CODE VAL LEN SIN COS TAN ASN ACS ATN LN EXP INT '
      'SQR SGN ABS PEEK IN USR STR$ CHR$ NOT BIN OR AND <= >= <> LINE THEN TO STEP DEF_FN CAT FORMAT MOVE '
      'ERASE OPEN_# CLOSE_# MERGE VERIFY BEEP CIRCLE INK PAPER FLASH BRIGHT INVERSE OVER OUT LPRINT LLIST '
      'STOP READ DATA RESTORE NEW BORDER CONTINUE DIM REM FOR GO_TO GO_SUB INPUT LOAD LIST LET PAUSE NEXT '
      'POKE PRINT PLOT RUN SAVE RANDOMIZE IF CLS DRAW CLEAR RETURN COPY').split()
TOK = {k.replace('_', ' '): 165 + i for i, k in enumerate(KW)}
assert TOK['COPY'] == 255 and TOK['RND'] == 165 and TOK['PRINT'] == 245
ORDER = sorted(TOK, key=len, reverse=True)

def num5(v):
    assert v == int(v) and -65535 <= v <= 65535, v
    v = int(v)
    return bytes([0, 0xFF if v < 0 else 0, (v & 0xFFFF) & 255, (v & 0xFFFF) >> 8, 0])

def line(text):
    out, i, n = bytearray(), 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = text.index('"', i + 1); out += text[i:j + 1].encode('latin-1'); i = j + 1; continue
        if c == ' ': i += 1; continue
        if c.isdigit() or (c == '.' and i + 1 < n and text[i + 1].isdigit()):
            if out and (chr(out[-1]).isalpha() or chr(out[-1]) == '$') and out[-1] < 128:
                out += c.encode(); i += 1; continue     # part of a name (not used here)
            j = i
            while j < n and (text[j].isdigit() or text[j] == '.'): j += 1
            out += text[i:j].encode() + b'\x0e' + num5(float(text[i:j])); i = j; continue
        for k in ORDER:
            if text.startswith(k, i):
                prev = text[i - 1] if i else ' '
                nxt = text[i + len(k)] if i + len(k) < n else ' '
                if k[0].isalpha() and (prev.isalpha() and prev.isupper()): continue
                if k[-1].isalpha() and nxt.isalpha() and nxt.isupper(): continue
                out.append(TOK[k]); i += len(k)
                if k == 'REM':
                    out += text[i:].lstrip(' ').encode('latin-1'); i = n
                break
        else:
            out += c.encode('latin-1'); i += 1
    return bytes(out)

def program(src):
    img = bytearray(); last = -1
    for l in src.splitlines():
        if not l.strip(): continue
        num, rest = l.strip().split(' ', 1); num = int(num); assert 0 < num < 10000 and num > last; last = num
        body = line(rest) + b'\r'
        img += struct.pack('>H', num) + struct.pack('<H', len(body)) + body
    return bytes(img)

def block(flag, data):
    x = bytes([flag]) + data; c = 0
    for b in x: c ^= b
    return x + bytes([c])
def header(typ, name, length, p1, p2):
    return block(0, bytes([typ]) + name.ljust(10)[:10].encode() + struct.pack('<HHH', length, p1, p2))
def write(stem, blocks):
    open(stem + '.tap', 'wb').write(b''.join(struct.pack('<H', len(b)) + b for b in blocks))
    open(stem + '.tzx', 'wb').write(b'ZXTape!\x1a\x01\x14' + b''.join(b'\x10' + struct.pack('<HH', 1000, len(b)) + b for b in blocks))
