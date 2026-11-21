#!/usr/bin/env python3
"""Text to allophones: the NRL (Elovitz et al., 1976, public domain) letter-to-
sound rules plus a small exceptions list, mapped to SP0256-AL2-style allophone
codes. This is the reference for the Z80 converter: same rules, same greedy
matcher, same output. encode() packs the rules for the Z80."""
import json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
RULES_JSON = os.path.join(HERE, '..', 'data', 'nrl', 'eng_to_ipa.json')

# SP0256-AL2 allophone names, codes 0-63 (public reference for names/numbering only)
NAMES = ('PA1 PA2 PA3 PA4 PA5 OY AY EH KK3 PP JH NN1 IH TT2 RR1 AX MM TT1 DH1 IY EY DD1 UW1 AO AA YY2 '
         'AE HH1 BB1 TH UH UW2 AW DD2 GG3 VV GG1 SH ZH RR2 FF KK2 KK1 ZZ NG LL WW XR WH YY1 CH ER1 ER2 '
         'OW DH2 SS NN2 HH2 OR AR YR GG2 EL BB2').split()
CODE = {n: i for i, n in enumerate(NAMES)}
STRESS = 0x40                   # on a vowel from the exceptions: the stressed one (cleared by postprocess)
QMARK = 0x44                    # '?' while converting: PA5 + a question flag (bit 6), cleared by postprocess
CODE['PAQ'] = QMARK
# NRL phoneme -> allophone(s)
PH = {'IY': 'IY', 'IH': 'IH', 'EY': 'EY', 'EH': 'EH', 'AE': 'AE', 'AA': 'AA', 'AO': 'AO', 'OW': 'OW', 'UH': 'UH',
      'UW': 'UW2', 'ER': 'ER1', 'AX': 'AX', 'AH': 'AX', 'AY': 'AY', 'AW': 'AW', 'OY': 'OY', 'Y': 'YY1', 'P': 'PP',
      'B': 'BB1', 'T': 'TT1', 'D': 'DD1', 'K': 'KK1', 'G': 'GG1', 'F': 'FF', 'V': 'VV', 'TH': 'TH', 'DH': 'DH1',
      'S': 'SS', 'Z': 'ZZ', 'SH': 'SH', 'ZH': 'ZH', 'HH': 'HH1', 'CH': 'CH', 'JH': 'JH', 'M': 'MM', 'N': 'NN1',
      'NX': 'NG', 'L': 'LL', 'W': 'WW', 'WH': 'WH', 'R': 'RR1',
      '< >': 'PA2', '<,>': 'PA4', '<.>': 'PA5', '<?>': 'PAQ', '<->': 'PA4'}
# exceptions: whole words, tried before the rules (they are rules with space contexts)
EXCEPTIONS = {   # a phoneme ending in 1 is the stressed one (pitch accent); otherwise the first vowel is
    'A': 'AX', 'THE': 'DH AX', 'OF': 'AX V', 'TO': 'T UW', 'DO': 'D UW', 'YOU': 'Y UW', 'ARE': 'AA R',
    'IS': 'IH Z', 'WAS': 'W AA Z', 'ONE': 'W AH N', 'TWO': 'T UW', 'SAID': 'S EH D', 'SAYS': 'S EH Z',
    'HAVE': 'HH AE V', 'GIVE': 'G IH V', 'LIVE': 'L IH V', 'COME': 'K AH M', 'SOME': 'S AH M',
    'HELLO': 'HH EH L OW1', 'NATHAN': 'N EY TH AX N', 'OPTICA': 'AA P T IH K AX', 'OPTICOS': 'AA P T IH K AO S', 'OPTICVOICE': 'AA1 P T IH K V OY S', 'VOICE': 'V OY S',
    'ZX': 'Z EH D EH1 K S', 'SPECTRUM': 'S P EH K T R AX M', 'TECHNOLOGY': 'T EH K N AA1 L AX JH IY',
    'DESIGN': 'D IH Z AY1 N', 'BASIC': 'B EY S IH K', 'COMPUTER': 'K AX M P Y UW1 T ER', 'SPEECH': 'S P IY CH',
    'SINCLAIR': 'S IH N K L EH R', 'BEEPER': 'B IY P ER', 'WORLD': 'W ER L D', 'OK': 'OW K EY1',
    # common irregular words the letter-to-sound rules get wrong
    'WHAT': 'W AA T', 'WHO': 'HH UW', 'WHERE': 'W EH R', 'THERE': 'DH EH R', 'THEIR': 'DH EH R', 'THEY': 'DH EY',
    'WERE': 'W ER', 'WORK': 'W ER K', 'WORD': 'W ER D', 'BEEN': 'B IH N', 'COULD': 'K UH D', 'WOULD': 'W UH D',
    'SHOULD': 'SH UH D', 'GOOD': 'G UH D', 'LOOK': 'L UH K', 'BOOK': 'B UH K', 'PUT': 'P UH T', 'FULL': 'F UH L',
    'ONCE': 'W AH N S', 'ANY': 'EH N IY', 'MANY': 'M EH N IY', 'AGAIN': 'AX G EH1 N', 'EYE': 'AY', 'BUY': 'B AY',
    'BUSY': 'B IH Z IY', 'FRIEND': 'F R EH N D', 'PEOPLE': 'P IY P AX L', 'WATER': 'W AO T ER', 'FOUR': 'F AO R',
    'YOUR': 'Y AO R', 'HOUR': 'AW ER', 'OUR': 'AW ER', 'KNOW': 'N OW', 'KEY': 'K IY', 'READY': 'R EH D IY',
    'HEAD': 'HH EH D', 'MORNING': 'M AO R N IH NX', 'COLOUR': 'K AH L ER', 'COLOR': 'K AH L ER',
    'ENOUGH': 'IH N AH1 F', 'THROUGH': 'TH R UW', 'THOUGH': 'DH OW', 'EIGHT': 'EY T', 'SEVEN': 'S EH V AX N',
    'ZERO': 'Z IY R OW', 'MACHINE': 'M AX SH IY1 N', 'PROGRAM': 'P R OW G R AE M', 'MEMORY': 'M EH M ER IY',
    'LOAD': 'L OW D', 'ROAD': 'R OW D', 'WOMAN': 'W UH M AX N', 'WOMEN': 'W IH M IH N', 'BROTHER': 'B R AH DH ER',
    'MOTHER': 'M AH DH ER', 'OTHER': 'AH DH ER', 'LOVE': 'L AH V', 'MOVE': 'M UW V', 'LOSE': 'L UW Z',
    'DONE': 'D AH N', 'GONE': 'G AO N', 'NONE': 'N AH N', 'LISTEN': 'L IH S AX N', 'OFTEN': 'AO F AX N',
    'ISLAND': 'AY L AX N D', 'LEARN': 'L ER N', 'EARLY': 'ER L IY', 'HEARD': 'HH ER D', 'VERY': 'V EH R IY',
    'REALLY': 'R IY L IY', 'ALREADY': 'AO L R EH1 D IY', 'LITTLE': 'L IH T AX L', 'GIRL': 'G ER L',
    'PLAYER': 'P L EY ER', 'HELP': 'HH EH L P', 'REAL': 'R IY L', 'ROLL': 'R OW L', 'WORRY': 'W ER R IY',
    'TODAY': 'T AX D EY1', 'BEGIN': 'B IH G IH1 N', 'BECAUSE': 'B IH K AO1 Z', 'ABOUT': 'AX B AW1 T',
    'HOTEL': 'HH OW T EH1 L', 'ZED': 'Z EH D',
}
VOWELS, CONS, VOICED, FRONT = set('AEIOUY'), set('BCDFGHJKLMNPQRSTVWXZ'), set('BDVGJLMNRWZ'), set('EIY')

def load_rules():
    d = json.load(open(RULES_JSON))
    groups = {}                                        # first char of the match -> [(left, match, right, out)]
    for g in d.values():
        for line in g:
            m = re.match(r"^(.*)\[(.+)\](.*)=/(.*)/$", line)
            left, match, right, out = m.groups()
            phon = [p for p in re.findall(r'<.>|[A-Z]+', out.replace('//', ' ').replace('/', ' '))]
            codes = [CODE[PH[p]] for p in phon]
            if match.isdigit(): codes.append(CODE['PA2'])          # a short gap after each spelt digit
            groups.setdefault(match[0], []).append((left, match, right, codes))
    for w, p in sorted(EXCEPTIONS.items(), key=lambda kv: -len(kv[0])):
        groups.setdefault(w[0], []).insert(0, (' ', w, ' ', [CODE[PH[x.rstrip('1')]] | (STRESS if x.endswith('1') else 0)
                                                           for x in p.split()]))
    return groups

def _left(pat, t, i):
    """match the left context pat leftwards ending at t[i]; greedy, no backtracking"""
    for c in reversed(pat):
        ch = t[i] if i >= 0 else ' '
        if c == ' ':
            if ch.isalpha(): return False
            i -= 1
        elif c == '#':
            if ch not in VOWELS: return False
            while i >= 0 and t[i] in VOWELS: i -= 1
        elif c == ':':
            while i >= 0 and t[i] in CONS: i -= 1
        elif c == '^':
            if ch not in CONS: return False
            i -= 1
        elif c == '.':
            if ch not in VOICED: return False
            i -= 1
        elif c == '+':
            if ch not in FRONT: return False
            i -= 1
        elif c in '&@':
            if ch in ('SCGZXJ' if c == '&' else 'TSRDLZNJ'): i -= 1
            elif ch == 'H' and i >= 1 and t[i - 1] in ('CS' if c == '&' else 'TCS'): i -= 2
            else: return False
        else:
            if ch != c: return False
            i -= 1
    return True

def _right(pat, t, i):
    n = len(t)
    for c in pat:
        ch = t[i] if i < n else ' '
        if c == ' ':
            if ch.isalpha(): return False
            i += 1
        elif c == '#':
            if ch not in VOWELS: return False
            while i < n and t[i] in VOWELS: i += 1
        elif c == ':':
            while i < n and t[i] in CONS: i += 1
        elif c == '^':
            if ch not in CONS: return False
            i += 1
        elif c == '.':
            if ch not in VOICED: return False
            i += 1
        elif c == '+':
            if ch not in FRONT: return False
            i += 1
        elif c == '%':
            for s in ('ING', 'ELY', 'ER', 'ES', 'ED', 'E'):
                if t.startswith(s, i): i += len(s); break
            else: return False
        elif c in '&@':
            if t.startswith('CH', i) or t.startswith('SH', i) or (c == '@' and t.startswith('TH', i)): i += 2
            elif ch in ('SCGZXJ' if c == '&' else 'TSRDLZNJ'): i += 1
            else: return False
        else:
            if ch != c: return False
            i += 1
    return True

def normalise(text):
    text = text.translate(str.maketrans('!;:', '.,,'))
    t = ''.join(c if (c.isascii() and c.isalnum()) or c in " ,.?-'" else ' ' for c in text.upper())
    return ' ' + re.sub(' +', ' ', t).strip() + ' '

def to_allophones(text, groups=None, trace=False, **post):
    groups = groups or load_rules(); t = normalise(text); i = 0; out = []
    while i < len(t):
        for left, match, right, o in groups.get(t[i], []):
            if t.startswith(match, i) and _left(left, t, i - 1) and _right(right, t, i + len(match)):
                if trace: print(repr(left), match, repr(right), [NAMES[x] for x in o])
                out += o; i += len(match); break
        else: i += 1                                   # no rule (e.g. a stray character): skip it
    # merge runs of pauses: keep the longest
    res = []
    for c in out:
        if c & 63 <= 4 and res and res[-1] & 63 <= 4: res[-1] = max(res[-1], c)
        else: res.append(c)
    while res and res[0] & 63 <= 4: res.pop(0)
    return postprocess(res, **post)

# ---- after the rules: context variants of the allophones, then intonation (pitch levels in
# bits 6-7: 0 mid, 1 low, 2 high). The Z80 converter does the same with the same tables.
CLS_P, CLS_C, CLS_F, CLS_B, CLS_L = range(5)       # pause, consonant, front vowel/glide, back vowel/glide, liquid
FRONTV = 'IY IH EY EH AE YR XR YY1 YY2'.split()
BACKV = 'AA AO OW UH UW1 UW2 AW OY OR AR AX ER1 ER2 AY EL WW WH'.split()
LIQ = 'LL RR1 RR2'.split()
VOWELS_A = set(FRONTV + BACKV) - {'YY1', 'YY2', 'WW', 'WH'}   # syllable nuclei (bit 7 of ctab)
def _cls(n):
    if n.startswith('PA'): return CLS_P
    return CLS_F if n in FRONTV else CLS_B if n in BACKV else CLS_L if n in LIQ else CLS_C
# family: members, then the variant for next class P C F B L when the previous allophone is not a
# consonant, then the same when it is
FAMILIES = [
    ('KK1 KK2 KK3', 'KK2 KK2 KK1 KK3 KK3', None), ('GG1 GG2 GG3', 'GG2 GG2 GG1 GG3 GG3', None),
    ('TT1 TT2', 'TT1 TT1 TT2 TT2 TT2', None), ('DD1 DD2', 'DD1 DD1 DD2 DD2 DD2', None),
    ('BB1 BB2', 'BB1 BB1 BB2 BB2 BB2', None), ('HH1 HH2', 'HH2 HH2 HH1 HH2 HH2', None),
    ('NN1 NN2', 'NN2 NN2 NN1 NN1 NN1', None), ('DH1 DH2', 'DH2 DH2 DH1 DH1 DH1', None),
    ('RR1 RR2', 'RR1 RR1 RR1 RR1 RR1', 'RR2 RR2 RR2 RR2 RR2'), ('LL EL', 'LL LL LL LL LL', 'EL EL LL LL LL')]
def variant_tables():
    """ctab[64] = class | family << 3; vtab = 10 bytes per family"""
    ctab = [_cls(n) | (0x80 if n in VOWELS_A else 0) for n in NAMES]; vtab = []
    for f, (mem, a, b) in enumerate(FAMILIES):
        for m in mem.split(): ctab[CODE[m]] |= (f + 1) << 3
        vtab += [CODE[x] for x in a.split()] + [CODE[x] for x in (b or a).split()]
    return ctab, vtab
CTAB, VTAB = variant_tables()
def postprocess(codes, variants=True, inton=True):
    c = list(codes)
    if variants:
        for i in range(len(c)):
            fam = CTAB[c[i] & 63] >> 3 & 15
            if not fam or c[i] & 0xC0: continue
            nxt = CTAB[c[i + 1] & 63] & 7 if i + 1 < len(c) else CLS_P
            prv = 5 if i and CTAB[c[i - 1] & 63] & 7 == CLS_C else 0
            c[i] = VTAB[(fam - 1) * 10 + prv + nxt]
    # intonation and word stress, word by word. The stressed vowel (marked in the exceptions,
    # else the first) of a word of two or more syllables gets the accent level; the rest the base:
    #   inside a sentence: base 0 (mid), accent 2 (high)
    #   last word before '.', '!' or the end: base 1 (low), accent 0 (a fall)
    #   last word before '?': base 2 (high), accent 3 (top)
    start = 0
    for i in range(len(c) + 1):
        p = c[i] if i < len(c) else 4
        if p & 63 > 4: continue
        kind = 2 if p == QMARK else 1 if p & 63 == 4 else 0
        word_levels(c, start, i, kind, inton)
        if i < len(c): c[i] = p & 63
        start = i + 1
    return c
def word_levels(c, start, end, kind, inton=True):
    base, acc = ((0, 2), (1, 0), (2, 3))[kind]
    vow = [j for j in range(start, end) if CTAB[c[j] & 63] & 0x80]
    s = next((j for j in range(start, end) if c[j] & STRESS), vow[0] if vow else None)
    for j in range(start, end):
        lv = (acc if len(vow) >= 2 and j == s else base) if inton else 0
        c[j] = (c[j] & 63) | lv << 6

# ---- packing for the Z80: each rule = left (reversed) | match | right | output, each part ending with bit 7
# set on its last byte; an empty part is a single $80. A group ends with $FF.
CLASS = {'#': 1, ':': 2, '^': 3, '.': 4, '+': 5, '%': 6, '&': 7, '@': 8, ' ': 9}
def _part(s, literal=False):
    b = [(ord(c) if literal else CLASS.get(c, ord(c))) if isinstance(c, str) else c for c in s]
    if not b: return [0x80]
    b[-1] |= 0x80; return b
def encode(groups):
    """returns (index of 40 chars ' ' .. 'Z' as offsets, rule bytes)"""
    data, index = [], {}
    for ch in sorted(groups):
        index[ch] = len(data)
        for left, match, right, out in groups[ch]:
            assert all(0 < x < 128 for x in out)  # PA1 never in a rule: $80 means an empty part
            data += _part(left[::-1]) + _part(match[1:], True) + _part(right) + _part(out)
        data.append(0xFF)
    return index, bytes(data)

if __name__ == '__main__':
    import sys
    g = load_rules()
    for s in sys.argv[1:] or ['HELLO NATHAN', 'OPTICA TECHNOLOGY DESIGN', 'I AM A ZX SPECTRUM']:
        print(s, '->', ' '.join(NAMES[c] for c in to_allophones(s, g)))
    idx, data = encode(g); print('rules:', sum(len(v) for v in g.values()), 'packed', len(data), 'bytes; groups', ''.join(sorted(idx)))
