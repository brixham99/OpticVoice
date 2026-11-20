#!/usr/bin/env python3
"""Phase 2 allophones: our own source-filter formant synthesiser (only the SP0256-AL2
names and numbering are used as a reference), rendered pitch-synchronously and coded
to 1 bit for the Spectrum beeper by optimising each stored pitch period against a
speaker-band error weighting (rather than plain delta-sigma).

Frame model (what the Z80 player plays): an allophone is a list of frames; a frame is
one pitch period of PERIOD bits (37 bytes) played `rep` times, a run of silent frames,
or (voiced frames) a period the player shortens or lengthens to change the pitch."""
import numpy as np
from scipy.signal import butter, sosfilt, lfilter
from front import NAMES
T_BIT = 112
FS = 3_500_000 / T_BIT          # 31,250 bits a second
PERIOD = 296                    # bits per stored pitch period (37 bytes): F0 = 105.6 Hz
F0 = FS / PERIOD
NBYTE = PERIOD // 8
PAD = 0xAA                      # what the player sends to lengthen a voiced period
PITCH_OFFS = (0, 4, -4, -7)     # bytes added to the period for pitch levels 0-3 (mid, low, high, top)

# formant targets F1 F2 F3 (Hz), adult male, after the usual published tables (Peterson &
# Barney 1952; Klatt 1980)
V = {'IY': (300, 2250, 2950), 'IH': (400, 1850, 2550), 'EH': (550, 1750, 2500), 'AE': (680, 1650, 2450),
     'AA': (720, 1150, 2500), 'AO': (590, 900, 2450), 'OW': (500, 950, 2350), 'UH': (450, 1100, 2300),
     'UW': (330, 950, 2250), 'AX': (620, 1250, 2500), 'ER': (480, 1330, 1650), 'SCH': (500, 1450, 2500),
     'LL': (360, 1050, 2750), 'RR': (320, 1100, 1450), 'WW': (300, 650, 2200), 'YY': (270, 2150, 3000),
     'FRONT': (420, 1900, 2600), 'BACK': (560, 1150, 2450)}
LOCUS = {'lab': (220, 900, 2150), 'alv': (220, 1750, 2650), 'velf': (260, 2250, 2850), 'velb': (260, 1450, 2350),
         'pal': (260, 2000, 2800), 'dent': (260, 1450, 2550), 'glot': None}
BW = (70, 100, 160, 250, 300)
F45 = (3350, 3900)

def vowel(d, a, b=None, amp=1.0, glide=(.3, .8)): return dict(k='v', dur=d, a=a, b=b or a, amp=amp, glide=glide, edge=True)
def liquid(d, a, b='SCH', amp=.9): return dict(k='v', dur=d, a=a, b=b, amp=amp, glide=(.45, 1.0))
def nasal(d, f, zero, amp=.6, end='SCH'): return dict(k='n', dur=d, f=f, zero=zero, amp=amp, end=end)
def fric(d, spec, amp, voiced=0., place='alv', end='SCH'): return dict(k='f', dur=d, spec=spec, amp=amp, voiced=voiced, place=place, end=end)
def stop(clos, burst, spec, place, voiced, asp, end='SCH', bamp=.7, trans=30):
    return dict(k='s', clos=clos, burst=burst, spec=spec, place=place, voiced=voiced, asp=asp, end=end, bamp=bamp, trans=trans)
def hh(d, end): return dict(k='h', dur=d, end=end)
A = {
 'PA1': dict(k='p', dur=10), 'PA2': dict(k='p', dur=40), 'PA3': dict(k='p', dur=60), 'PA4': dict(k='p', dur=120),
 'PA5': dict(k='p', dur=220),
 'IY': vowel(190, 'IY'), 'IH': vowel(110, 'IH'), 'EH': vowel(120, 'EH'), 'AE': vowel(170, 'AE'), 'AA': vowel(180, 'AA'),
 'AO': vowel(170, 'AO'), 'UH': vowel(120, 'UH'), 'AX': vowel(90, 'AX'), 'UW1': vowel(120, 'UW'), 'UW2': vowel(200, 'UW'),
 'ER1': vowel(150, 'ER'), 'ER2': vowel(230, 'ER'),
 'EY': vowel(220, 'EH', 'IY'), 'AY': vowel(250, 'AA', 'IY'), 'OY': vowel(280, 'AO', 'IY'), 'AW': vowel(270, 'AA', 'UW'),
 'OW': vowel(220, 'OW', 'UW', glide=(.45, .95)), 'OR': vowel(250, 'AO', 'ER'), 'AR': vowel(250, 'AA', 'ER'),
 'YR': vowel(250, 'IY', 'ER'), 'XR': vowel(250, 'EH', 'ER'), 'EL': vowel(170, 'SCH', 'LL', glide=(.2, .7)),
 'LL': liquid(80, 'LL'), 'RR1': liquid(90, 'RR'), 'RR2': liquid(70, 'RR'), 'WW': liquid(90, 'WW'),
 'YY1': liquid(70, 'YY'), 'YY2': liquid(100, 'YY'),
 'MM': nasal(100, (270, 1100, 2150), 900), 'NN1': nasal(90, (270, 1700, 2600), 1500),
 'NN2': nasal(120, (270, 1700, 2600), 1500, end=None), 'NG': nasal(120, (270, 2100, 2700), 2600, end=None),
 'SS': fric(130, [(4600, 1800, 1.0)], .55), 'ZZ': fric(110, [(4600, 1800, 1.0)], .35, .55),
 'SH': fric(140, [(2700, 900, 1.0), (4200, 1500, .5)], .6, place='pal'),
 'ZH': fric(110, [(2700, 900, 1.0), (4200, 1500, .5)], .4, .55, place='pal'),
 'FF': fric(110, [(1500, 3000, .5), (4500, 4000, .6)], .16, place='lab'),
 'VV': fric(80, [(1500, 3000, .5), (4500, 4000, .6)], .12, .7, place='lab'),
 'TH': fric(110, [(1800, 3000, .5), (5000, 4000, .6)], .13, place='dent'),
 'DH1': fric(60, [(1800, 3000, .5), (5000, 4000, .6)], .10, .75, place='dent'),
 'DH2': fric(80, [(1800, 3000, .5), (5000, 4000, .6)], .10, .75, place='dent', end=None),
 'HH1': hh(70, 'FRONT'), 'HH2': hh(80, 'BACK'), 'WH': dict(k='h', dur=70, end='WW', start='WW'),
 # stops: closure ms, burst ms, burst spectrum, place, voiced, aspiration ms, transition target
 'PP': stop(60, 8, [(1000, 1800, 1.0)], 'lab', False, 45, bamp=.45),
 'BB1': stop(45, 6, [(1000, 1800, 1.0)], 'lab', True, 0, end=None, bamp=.3, trans=0),
 'BB2': stop(35, 6, [(1000, 1800, 1.0)], 'lab', True, 0, bamp=.35),
 'TT1': stop(55, 10, [(4500, 3000, 1.0)], 'alv', False, 12, end=None, bamp=.5, trans=0),
 'TT2': stop(60, 12, [(4500, 3000, 1.0)], 'alv', False, 50, bamp=.7),
 'DD1': stop(40, 8, [(4000, 3000, 1.0)], 'alv', True, 0, end=None, bamp=.35, trans=0),
 'DD2': stop(35, 8, [(4000, 3000, 1.0)], 'alv', True, 0, bamp=.45),
 'KK1': stop(60, 14, [(2900, 900, 1.0)], 'velf', False, 50, end='FRONT', bamp=.7),
 'KK2': stop(60, 14, [(2200, 1200, 1.0)], 'velf', False, 15, end=None, bamp=.55, trans=0),
 'KK3': stop(60, 14, [(1600, 700, 1.0)], 'velb', False, 50, end='BACK', bamp=.7),
 'GG1': stop(35, 10, [(2900, 900, 1.0)], 'velf', True, 0, end='FRONT', bamp=.45),
 'GG2': stop(40, 10, [(2200, 1200, 1.0)], 'velf', True, 0, end=None, bamp=.4, trans=0),
 'GG3': stop(35, 10, [(1600, 700, 1.0)], 'velb', True, 0, end='BACK', bamp=.45),
 'CH': dict(k='a', clos=50, fdur=100, spec=[(2700, 900, 1.0), (4200, 1500, .5)], voiced=0., amp=.65),
 'JH': dict(k='a', clos=35, fdur=80, spec=[(2700, 900, 1.0), (4200, 1500, .5)], voiced=.55, amp=.45),
}
assert set(A) == set(NAMES), set(NAMES) ^ set(A)

RATE = 0.85                     # duration scale
def ms(d): return int(round(d * RATE / 1000 * FS))
def periods(d): return max(1, int(round(d * RATE / 1000 * F0)))
def reson(x, f, bw):
    """2-pole resonator with unity gain at DC; f may vary per sample"""
    f = np.broadcast_to(np.asarray(f, float), x.shape)
    c = -np.exp(-2 * np.pi * bw / FS); b = 2 * np.exp(-np.pi * bw / FS) * np.cos(2 * np.pi * f / FS); a = 1 - b - c
    if np.all(f == f[0]): return lfilter([a[0]], [1, -b[0], -c], x)
    y = np.zeros_like(x); y1 = y2 = 0.0
    for n in range(len(x)):
        y0 = a[n] * x[n] + b[n] * y1 + c * y2; y[n] = y0; y2, y1 = y1, y0
    return y
def antireson(x, f, bw):
    c = -np.exp(-2 * np.pi * bw / FS); b = 2 * np.exp(-np.pi * bw / FS) * np.cos(2 * np.pi * f / FS); a = 1 - b - c
    return lfilter([1 / a, -b / a, -c / a], [1], x)
def glottal(n):
    """glottal flow derivative, closure (the main excitation) just after each period start"""
    t = (np.arange(n) / PERIOD + .53) % 1.0
    g = np.where(t < .4, .5 - .5 * np.cos(np.pi * t / .4), np.where(t < .56, np.cos(np.pi * (t - .4) / .32), 0.0))
    d = np.diff(g, prepend=g[0]); return lfilter([1], [1, -.6], d)          # some spectral tilt
def noise(n, rng): return rng.standard_normal(n)
def shaped_noise(n, spec, rng):
    x = noise(n, rng); y = np.zeros(n)
    for f, bw, g in spec: y += g * reson(x, f, bw)
    y = sosfilt(butter(2, 900, 'highpass', fs=FS, output='sos'), y)
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-9)
def track(a, b, n, glide=(0., 1.)):
    a, b = np.array(a, float), np.array(b, float); w = np.clip((np.linspace(0, 1, n) - glide[0]) / max(1e-6, glide[1] - glide[0]), 0, 1)
    w = 3 * w ** 2 - 2 * w ** 3; return a + (b - a) * w[:, None]
def tract(src, tr):
    y = src
    for k in range(3): y = reson(y, tr[:, k], BW[k])
    for k in range(2): y = reson(y, F45[k], BW[3 + k])
    return y
def voiced(n, tr): y = tract(glottal(n), tr); return y / (np.sqrt(np.mean(y ** 2)) + 1e-9)
def ramp(n, a=.004, r=.004):
    e = np.ones(n); a, r = min(n, max(1, ms(a * 1000))), min(n, max(1, ms(r * 1000)))
    e[:a] *= np.linspace(0, 1, a); e[-r:] *= np.linspace(1, 0, r); return e
EDGE = 0.5                      # how far vowel edges move towards neutral
def tgt(name): return V[name] if name else None

def synth(name):
    """float signal for one allophone, length a whole number of periods for voiced parts.
    Returns a list of (kind, samples) parts: kind 'v' voiced (pitch-scalable), 'u' unvoiced, 's' silence"""
    rng = np.random.default_rng(1000 + NAMES.index(name)); p = A[name]; k = p['k']
    if k == 'p': return [('s', np.zeros(periods(p['dur']) * PERIOD))]
    if k == 'v':
        n = periods(p['dur']) * PERIOD; tr = track(V[p['a']], V[p['b']], n, p['glide'])
        if p.get('edge') and EDGE:                  # blended joins: glide in from / out towards neutral
            e = min(ms(30), n // 3); w = np.zeros(n); w[:e] = np.linspace(EDGE, 0, e) ** 2 / EDGE; w[-e:] = np.linspace(0, EDGE, e) ** 2 / EDGE
            tr = tr + (np.array(V['SCH'], float) - tr) * w[:, None]
        return [('v', voiced(n, tr) * p['amp'] * ramp(n, .003, .006))]
    if k == 'n':
        n = periods(p['dur']) * PERIOD; tr = track(p['f'], tgt(p['end']) or p['f'], n, (.75, 1.0))
        y = antireson(tract(glottal(n), tr), p['zero'], 200); y = reson(y, 250, 120)
        return [('v', y / np.sqrt(np.mean(y ** 2)) * p['amp'] * ramp(n, .006, .006))]
    if k == 'f':
        n = periods(p['dur']) * PERIOD; y = shaped_noise(n, p['spec'], rng) * p['amp'] * ramp(n, .02, .025)
        if p['voiced']:
            tr = track(LOCUS[p['place']], tgt(p['end']) or LOCUS[p['place']], n, (.6, 1.0)); v = voiced(n, tr)
            v = sosfilt(butter(2, 1200, fs=FS, output='sos'), v)
            ph = (np.arange(n) / PERIOD) % 1.0; y = y * (.4 + .6 * (ph < .5))
            y = y + v / np.sqrt(np.mean(v ** 2)) * p['voiced'] * .45 * ramp(n, .01, .01)
            return [('v', y)]
        return [('u', y)]
    if k == 'h':
        n = periods(p['dur']) * PERIOD; tr = track(V[p.get('start', p['end'])], V[p['end']], n)
        y = tract(noise(n, rng), tr); y = y / np.sqrt(np.mean(y ** 2)) * .3 * ramp(n, .015, .01)
        return [('u', y)]
    if k == 's':
        parts = []; c = ms(p['clos'])
        if p['voiced']:
            cn = periods(p['clos']) * PERIOD
            vb = sosfilt(butter(2, 400, fs=FS, output='sos'), glottal(cn)); vb = vb / np.sqrt(np.mean(vb ** 2)) * .1
            parts.append(('v', vb))
        else: parts.append(('s', np.zeros(max(1, round(c / PERIOD)) * PERIOD)))
        b = ms(p['burst']); burst = shaped_noise(b, p['spec'], rng) * p['bamp'] * np.exp(-np.arange(b) / max(1, b / 2.5))
        loc = LOCUS[p['place']]; end = tgt(p['end']) or V['SCH']
        if p['asp']:
            a = ms(p['asp']); tr = track(loc, end, a); asp = tract(noise(a, rng), tr)
            asp = asp / np.sqrt(np.mean(asp ** 2)) * .28 * np.linspace(1, .5, a)
            u = np.concatenate([burst, asp])
        else: u = burst
        nu = -(-len(u) // PERIOD) * PERIOD; u = np.append(u, np.zeros(nu - len(u)))
        if p['voiced'] and p['trans']:
            u[b:] = 0; parts.append(('u', u[:PERIOD * max(1, -(-b // PERIOD))]))
            tn = periods(p['trans']) * PERIOD; parts.append(('v', voiced(tn, track(loc, end, tn)) * .7 * ramp(tn, .002, .004)))
        else: parts.append(('u', u))
        return parts
    if k == 'a':
        f = periods(p['fdur']) * PERIOD; y = shaped_noise(f, p['spec'], rng) * p['amp'] * ramp(f, .004, .03)
        parts = [('s', np.zeros(max(1, round(ms(p['clos']) / PERIOD)) * PERIOD))]
        if p['voiced']:
            v = sosfilt(butter(2, 1200, fs=FS, output='sos'), voiced(f, track(LOCUS['pal'], V['SCH'], f)))
            y = y + v / np.sqrt(np.mean(v ** 2)) * p['voiced'] * .5 * ramp(f, .01, .02); parts.append(('v', y))
        else: parts.append(('u', y))
        return parts
    raise ValueError(name)

# ---- 1-bit coding
LEVEL = 0.95                    # target amplitude (the 1-bit output is +-1)
DRIVE = 1.5                     # soft clip (tanh) after the gain: lowers the crest factor
GAIN = 0.32                     # RMS of a full-level vowel before the soft clip
PRE = 0.95                      # pre-emphasis y[n] = x[n] - PRE x[n-1]: lifts F2/F3 above the 1-bit noise
def shape(x):
    if PRE: x = lfilter([1, -PRE], [1], x) / (1 - PRE) * 1.0
    return np.tanh(x * GAIN * DRIVE) / np.tanh(DRIVE) * LEVEL

def weight_spectrum(L=PERIOD):
    """|W(f)|^2 on the L-point DFT grid: the error weighting (speaker band, 100 Hz - 5 kHz)"""
    f = np.fft.rfftfreq(L, 1 / FS); w = 1 / (1 + (f / 4500) ** 8) * (f > 60) * (1 / (1 + (90 / (f + 1e-9)) ** 4))
    return w
_R = {}
def optimise(t, iters=20000, K=12):
    """bits b in {-1,+1} of length L (one period, treated as circular) minimising the
    weighted error (b-t)^T R (b-t).  Start from first-order delta-sigma, then greedy
    moves: single-bit flips and flips of a pair of opposite bits up to K apart (moving
    an edge), which a low-pass weighting makes cheap."""
    L = len(t)
    if L not in _R: _R[L] = np.fft.irfft(weight_spectrum(L), L)
    r = _R[L]; b = np.where(dsm(np.tile(t, 2))[L:] > 0, 1., -1.)
    e = b - t; g = np.fft.irfft(np.fft.rfft(e) * np.fft.rfft(r), L)
    for _ in range(iters):
        d1 = -4 * b * g + 4 * r[0]; best = d1.min(); mv = (int(np.argmin(d1)), None)
        for k in range(1, K + 1):
            bj, gj = np.roll(b, -k), np.roll(g, -k)
            d2 = np.where(b != bj, -4 * (b * g + bj * gj) + 8 * r[0] + 8 * b * bj * r[k], np.inf)
            i = int(np.argmin(d2))
            if d2[i] < best: best, mv = d2[i], (i, (i + k) % L)
        if best >= -1e-9: break
        for i in mv:
            if i is None: continue
            delta = -2 * b[i]; b[i] = -b[i]; g += delta * np.roll(r, i)
    return (b > 0).astype(np.uint8)
def dsm(x):
    q = 0.0; b = np.zeros(len(x), np.uint8)
    for i, v in enumerate(x):
        u = v - q; o = 1.0 if u > 0 else -1.0; q = o - u; b[i] = o > 0
    return b
CODER = 'opt'                   # 'opt' (optimised periods), 'gs' (phase-free) or 'dsm'
GS_ITERS = 12
GS_GAIN = 1.0
def code(seg):
    return optimise(seg) if CODER == 'opt' else dsm(seg)
def code_part(segs):
    """code a run of target periods. 'gs': keep each period's harmonic magnitudes in the
    speaker band but let the phases move to whatever 1-bit patterns reproduce best
    (alternating projections), seeding each period with the previous one's phases"""
    if CODER != 'gs': return [code(s) for s in segs]
    L = PERIOD; f = np.fft.rfftfreq(L, 1 / FS); band = (f > 60) & (f < 5000); out = []; ph = None
    for t in segs:
        T = np.fft.rfft(t); mag = np.abs(T) * GS_GAIN
        phase = np.angle(T) if ph is None else ph
        best = None
        for it in range(GS_ITERS):
            X = np.where(band, mag * np.exp(1j * phase), 0); x = np.fft.irfft(X, L)
            b = optimise(x); B = np.fft.rfft(b * 2.0 - 1)
            err = np.sum(weight_spectrum(L) * (np.abs(B) - mag) ** 2)
            if best is None or err < best[0]: best = (err, b, np.angle(B))
            phase = np.angle(B)
        out.append(best[1]); ph = best[2]
    return out

HOP = {'v': 2, 'u': 1}
def hop_for(name, kind):
    p = A[name]
    if kind == 'u': return 2 if p['k'] in ('f', 'h') else 1
    if p['k'] == 'v' and p['a'] == p['b']: return 3
    return 2
def frames(name):
    """[(rep, bits or None, voiced)]"""
    out = []
    for kind, x in synth(name):
        n = len(x) // PERIOD
        if kind == 's':
            out.append((n, None, False)); continue
        x = shape(x); hop = hop_for(name, kind)
        ks = list(range(0, n, hop)); segs = [x[k * PERIOD:(k + 1) * PERIOD] for k in ks]
        live = [np.abs(sg).max() >= 0.01 for sg in segs]
        coded = iter(code_part([sg for sg, l in zip(segs, live) if l]) if kind == 'v' else
                     [code(sg) for sg, l in zip(segs, live) if l])
        for k, l in zip(ks, live):
            rep = min(hop, n - k); fr = next(coded) if l else None
            out.append((rep, fr, kind == 'v' and fr is not None))
    res = []                                        # merge silent runs
    for f in out:
        if res and f[1] is None and res[-1][1] is None: res[-1] = (res[-1][0] + f[0], None, False)
        else: res.append(f)
    return res
_F = {}
def build_frames():
    if not _F:
        for n in NAMES: _F[n] = frames(n)
    return _F
def frames_bytes(fr): return sum(1 + (NBYTE if b is not None else 0) for r, b, v in fr) + 1
PADBITS = np.unpackbits(np.array([PAD], np.uint8))
def play_bits(codes, F=None, pitch=NBYTE):
    """the bit stream the Z80 player sends for an allophone list (codes with pitch level in bits 6-7)"""
    F = F or build_frames(); out = []; last = 0
    for c in codes:
        lv, name = c >> 6, NAMES[c & 63]; L = (pitch + PITCH_OFFS[lv]) & 255; L = max(L, 8); nd, npd = min(L, NBYTE), max(0, L - NBYTE)
        for rep, b, v in F[name]:
            if b is None: seg = np.full(PERIOD * rep, last, np.uint8)
            else:
                one = np.concatenate([b[:8 * nd], np.tile(PADBITS, npd)]) if v else b
                seg = np.tile(one, rep)
            out.append(seg); last = seg[-1]
    return np.concatenate(out) if out else np.zeros(0, np.uint8)
def render_codes(codes, mode='bits'):
    if mode == 'bits': return play_bits(codes)
    F = []
    for c in codes:
        for kind, x in synth(NAMES[c & 63]): F.append(shape(x))
    return np.concatenate(F)
if __name__ == '__main__':
    import time; t = time.time(); F = build_frames()
    print('allophone data %d bytes, %.1f s' % (sum(frames_bytes(F[n]) for n in NAMES), time.time() - t))

# ---- AY-3-8912 (128K): sample playback through the three channel volume registers
# (tone and noise off, so each channel outputs its volume level). One byte per sample
# indexes a table of 256 (A, B, C) volume triples sorted by their summed level.
T_AY = 259                      # T-states per sample: 128 samples = one 296-bit period exactly
FS_AY = 3_500_000 / T_AY        # 13,513.5 Hz
PERIOD_AY = PERIOD * T_BIT // T_AY      # 128
# AY volume DAC levels (Fuse's table, after M. Westcott's measurements), 0..1
AY_LEVELS = np.array([0x0000, 0x0385, 0x053D, 0x0770, 0x0AD7, 0x0FD5, 0x15B0, 0x230C,
                      0x2B4C, 0x43C1, 0x5A4B, 0x732F, 0x9204, 0xAFF1, 0xD921, 0xFFFF]) / 0xFFFF
def ay_table():
    """256 (a, b, c) triples, ascending summed level, spread as evenly as the DAC allows"""
    tri = np.array([(a, b, c) for a in range(16) for b in range(16) for c in range(16)])
    s = AY_LEVELS[tri].sum(1); order = np.argsort(s, kind='stable'); tri, s = tri[order], s[order]
    pick = []
    for t in np.linspace(0, 3, 256):
        i = int(np.argmin(np.abs(s - t)))
        while i in pick and i + 1 < len(s): i += 1
        pick.append(i)
    pick = sorted(set(pick))
    cand = [i for i in range(len(s)) if i not in set(pick)]
    while len(pick) < 256:                       # fill the widest gaps with the triple nearest their middle
        ps = s[pick]; gaps = np.diff(ps); k = int(np.argmax(gaps)); mid = (ps[k] + ps[k + 1]) / 2
        j = min(cand, key=lambda i: abs(s[i] - mid)); cand.remove(j); pick = sorted(pick + [j])
    return tri[pick], s[pick]
AY_TRI, AY_SUM = ay_table()
AY_MID = 1.35                   # the summed level that stands for zero (silence, pads)
AY_SPAN = 1.25                  # +-1.0 of the shaped signal maps to MID +- SPAN
AY_PAD = int(np.argmin(np.abs(AY_SUM - AY_MID)))
AY_PRE, AY_DRIVE, AY_GAIN = 0.7, 1.2, 0.32
def ay_shape(x):
    if AY_PRE: x = lfilter([1, -AY_PRE], [1], x) / (1 - AY_PRE)
    return np.tanh(x * AY_GAIN * AY_DRIVE) / np.tanh(AY_DRIVE)
def ay_resample(seg):
    X = np.fft.rfft(seg); n = PERIOD_AY // 2 + 1
    Y = X[:n] * (PERIOD_AY / PERIOD); Y[-1] = Y[-1].real
    return np.fft.irfft(Y, PERIOD_AY)
def ay_quant(x, e0=0.0):
    """nearest table level with first-order error feedback; returns indexes and the carried error"""
    out = np.zeros(len(x), np.uint8); e = e0; t = AY_MID + AY_SPAN * x
    for i, v in enumerate(t):
        u = v - e; k = int(np.clip(np.searchsorted(AY_SUM, u), 1, 255))
        if abs(AY_SUM[k - 1] - u) < abs(AY_SUM[k] - u): k -= 1
        out[i] = k; e = AY_SUM[k] - u
    return out, e
def frames_ay(name):
    """as frames(), with 128 one-byte AY samples per period"""
    out = []
    for kind, x in synth(name):
        n = len(x) // PERIOD
        if kind == 's': out.append((n, None, False)); continue
        x = ay_shape(x); hop = hop_for(name, kind); e = 0.0
        for k in range(0, n, hop):
            rep = min(hop, n - k); seg = x[k * PERIOD:(k + 1) * PERIOD]
            if np.abs(seg).max() < 0.01: out.append((rep, None, False)); continue
            q, e = ay_quant(ay_resample(seg), e)
            out.append((rep, q, kind == 'v'))
    res = []
    for f in out:
        if res and f[1] is None and res[-1][1] is None: res[-1] = (res[-1][0] + f[0], None, False)
        else: res.append(f)
    return res
_FA = {}
def build_frames_ay():
    if not _FA:
        for n in NAMES: _FA[n] = frames_ay(n)
    return _FA
def ay_len(pitch, lv):
    """samples in a voiced AY period for PITCH (bytes, 37 = normal) and level lv (as the Z80)"""
    d = (pitch + PITCH_OFFS[lv] - NBYTE) & 255; d = d - 256 if d >= 128 else d
    return max(16, PERIOD_AY + ((d * 7) >> 1))
def play_ay(codes, F=None, pitch=NBYTE):
    """the AY summed output level per sample (FS_AY) the Z80 AY player produces"""
    F = F or build_frames_ay(); out = []; last = AY_PAD
    for c in codes:
        lv, name = c >> 6, NAMES[c & 63]; L = ay_len(pitch, lv)
        for rep, q, v in F[name]:
            if q is None: seg = np.full(PERIOD_AY * rep, last, np.uint8)
            else:
                one = (np.concatenate([q[:L], np.full(max(0, L - PERIOD_AY), AY_PAD, np.uint8)]) if v else q)
                seg = np.tile(one, rep)
            out.append(seg); last = seg[-1]
    idx = np.concatenate(out) if out else np.zeros(1, np.uint8)
    return AY_SUM[idx]
