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
# NRL phoneme -> allophone(s)
PH = {'IY': 'IY', 'IH': 'IH', 'EY': 'EY', 'EH': 'EH', 'AE': 'AE', 'AA': 'AA', 'AO': 'AO', 'OW': 'OW', 'UH': 'UH',
      'UW': 'UW2', 'ER': 'ER1', 'AX': 'AX', 'AH': 'AX', 'AY': 'AY', 'AW': 'AW', 'OY': 'OY', 'Y': 'YY1', 'P': 'PP',
      'B': 'BB1', 'T': 'TT1', 'D': 'DD1', 'K': 'KK1', 'G': 'GG1', 'F': 'FF', 'V': 'VV', 'TH': 'TH', 'DH': 'DH1',
      'S': 'SS', 'Z': 'ZZ', 'SH': 'SH', 'ZH': 'ZH', 'HH': 'HH1', 'CH': 'CH', 'JH': 'JH', 'M': 'MM', 'N': 'NN1',
      'NX': 'NG', 'L': 'LL', 'W': 'WW', 'WH': 'WH', 'R': 'RR1',
      '< >': 'PA2', '<,>': 'PA4', '<.>': 'PA5', '<?>': 'PA5', '<->': 'PA4'}
# exceptions: whole words, tried before the rules (they are rules with space contexts)
EXCEPTIONS = {
    'A': 'AX', 'THE': 'DH AX', 'OF': 'AX V', 'TO': 'T UW', 'DO': 'D UW', 'YOU': 'Y UW', 'ARE': 'AA R',
    'IS': 'IH Z', 'WAS': 'W AA Z', 'ONE': 'W AH N', 'TWO': 'T UW', 'SAID': 'S EH D', 'SAYS': 'S EH Z',
    'HAVE': 'HH AE V', 'GIVE': 'G IH V', 'LIVE': 'L IH V', 'COME': 'K AH M', 'SOME': 'S AH M',
    'HELLO': 'HH EH L OW', 'NATHAN': 'N EY TH AX N', 'OPTICA': 'AA P T IH K AX', 'OPTICOS': 'AA P T IH K AO S',
    'ZX': 'Z EH D EH K S', 'SPECTRUM': 'S P EH K T R AX M', 'TECHNOLOGY': 'T EH K N AA L AX JH IY',
    'DESIGN': 'D IH Z AY N', 'BASIC': 'B EY S IH K', 'COMPUTER': 'K AX M P Y UW T ER', 'SPEECH': 'S P IY CH',
    'SINCLAIR': 'S IH N K L EH R', 'BEEPER': 'B IY P ER', 'WORLD': 'W ER L D', 'OK': 'OW K EY',
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
        groups.setdefault(w[0], []).insert(0, (' ', w, ' ', [CODE[PH[x]] for x in p.split()]))
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
    t = ''.join(c if c.isalnum() or c in " ,.?-'" else ' ' for c in text.upper())
    return ' ' + re.sub(' +', ' ', t).strip() + ' '

def to_allophones(text, groups=None, trace=False):
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
        if c <= 4 and res and res[-1] <= 4: res[-1] = max(res[-1], c)
        else: res.append(c)
    while res and res[0] <= 4: res.pop(0)
    return res

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
            assert 0 not in out          # PA1 never in a rule: $80 means an empty part
            data += _part(left[::-1]) + _part(match[1:], True) + _part(right) + _part(out)
        data.append(0xFF)
    return index, bytes(data)

if __name__ == '__main__':
    import sys
    g = load_rules()
    for s in sys.argv[1:] or ['HELLO NATHAN', 'OPTICA TECHNOLOGY DESIGN', 'I AM A ZX SPECTRUM']:
        print(s, '->', ' '.join(NAMES[c] for c in to_allophones(s, g)))
    idx, data = encode(g); print('rules:', sum(len(v) for v in g.values()), 'packed', len(data), 'bytes; groups', ''.join(sorted(idx)))
