#!/usr/bin/env python3
"""Pre-synthesise the 64 allophones (our own waveforms; only the SP0256-AL2 names,
numbering and rough durations are used as a reference) with a small source-filter
formant synthesiser, then quantise each to 1 bit for the Spectrum beeper.
FS is the player's sample rate: 3,500,000 / T_BIT."""
import numpy as np
from front import NAMES
T_BIT = 112                     # T-states per output bit
FS = 3_500_000 / T_BIT          # 31,250 Hz
PERIOD = 296                    # bits per pitch period = one frame (37 bytes)
F0 = FS / PERIOD                # 105.57 Hz, so every frame starts a glottal cycle
rng = np.random.default_rng(1234)

V = {  # vowel targets F1 F2 F3 (Hz), adult male, rounded from the usual published tables
 'IY': (280, 2250, 2900), 'IH': (400, 1900, 2550), 'EY': (480, 1950, 2600), 'EH': (550, 1770, 2500),
 'AE': (680, 1650, 2450), 'AA': (720, 1100, 2450), 'AO': (580, 860, 2400), 'OW': (500, 880, 2350),
 'UH': (440, 1050, 2250), 'UW': (320, 900, 2250), 'AX': (600, 1250, 2450), 'ER': (480, 1350, 1700),
 'schwa': (500, 1450, 2450), 'RR': (330, 1050, 1400), 'LL': (380, 1000, 2700), 'WW': (300, 650, 2200),
 'YY': (260, 2200, 3000), 'MM': (270, 1050, 2200), 'NN': (270, 1650, 2600), 'NG': (270, 2200, 2700)}
BW = (80, 110, 170)
F4 = 3500                       # fixed upper formants add presence

def vowel(dur, a, b=None, amp=1.0): return dict(k='voice', dur=dur, f0=V[a], f1=V[b or a], amp=amp)
def nasal(dur, a): return dict(k='voice', dur=dur, f0=V[a], f1=V[a], amp=.45, nasal=True)
def fric(dur, lo, hi, amp=.6, voiced=0.): return dict(k='fric', dur=dur, band=(lo, hi), amp=amp, voiced=voiced)
def stop(clos, burst, band, asp=0, voiced=False, amp=.7):
    return dict(k='stop', clos=clos, burst=burst, band=band, asp=asp, voiced=voiced, amp=amp, dur=clos + burst + asp)
def affr(clos, dur, band, voiced=0.): return dict(k='affr', clos=clos, fdur=dur, band=band, voiced=voiced, dur=clos + dur)
A = {  # durations in ms, roughly following the SP0256-AL2's
 'PA1': dict(k='pause', dur=10), 'PA2': dict(k='pause', dur=30), 'PA3': dict(k='pause', dur=50),
 'PA4': dict(k='pause', dur=100), 'PA5': dict(k='pause', dur=200),
 'OY': vowel(300, 'AO', 'IY'), 'AY': vowel(260, 'AA', 'IY'), 'EH': vowel(110, 'EH'), 'IH': vowel(100, 'IH'),
 'AX': vowel(100, 'AX'), 'IY': vowel(200, 'IY'), 'EY': vowel(230, 'EH', 'IY'), 'UW1': vowel(110, 'UW'),
 'UW2': vowel(220, 'UW'), 'AO': vowel(160, 'AO'), 'AA': vowel(170, 'AA'), 'AE': vowel(160, 'AE'),
 'UH': vowel(110, 'UH'), 'AW': vowel(300, 'AA', 'UW'), 'OW': vowel(240, 'OW', 'UW'),
 'ER1': vowel(150, 'ER'), 'ER2': vowel(260, 'ER'), 'OR': vowel(280, 'AO', 'ER'), 'AR': vowel(260, 'AA', 'ER'),
 'YR': vowel(280, 'IY', 'ER'), 'XR': vowel(280, 'EH', 'ER'), 'EL': vowel(180, 'schwa', 'LL'),
 'RR1': vowel(110, 'RR', 'schwa', .8), 'RR2': vowel(90, 'RR', 'schwa', .8), 'LL': vowel(90, 'LL', 'schwa', .8),
 'WW': vowel(110, 'WW', 'schwa', .8), 'YY1': vowel(90, 'YY', 'schwa', .8), 'YY2': vowel(140, 'YY', 'schwa', .8),
 'MM': nasal(110, 'MM'), 'NN1': nasal(100, 'NN'), 'NN2': nasal(140, 'NN'), 'NG': nasal(140, 'NG'),
 'SS': fric(130, 4000, 8000, .45), 'SH': fric(140, 1800, 5500, .5), 'FF': fric(120, 1000, 7500, .15),
 'TH': fric(120, 1300, 7500, .12), 'ZZ': fric(120, 4000, 8000, .35, .5), 'ZH': fric(120, 1800, 5500, .4, .5),
 'VV': fric(90, 900, 3500, .3, .7), 'DH1': fric(70, 1200, 3600, .3, .7), 'DH2': fric(100, 1200, 3600, .3, .7),
 'HH1': dict(k='hh', dur=80), 'HH2': dict(k='hh', dur=110), 'WH': dict(k='hh', dur=90, glide='WW'),
 'PP': stop(70, 12, (300, 1500), 35), 'BB1': stop(40, 10, (300, 1500), 0, True), 'BB2': stop(25, 8, (300, 1500), 0, True),
 'TT1': stop(60, 15, (3000, 7000), 45), 'TT2': stop(70, 15, (3000, 7000), 60), 'DD1': stop(40, 12, (2500, 6000), 0, True),
 'DD2': stop(60, 12, (2500, 6000), 0, True), 'KK1': stop(60, 18, (1800, 3000), 45), 'KK2': stop(70, 18, (1400, 2400), 50),
 'KK3': stop(70, 18, (1000, 2000), 50), 'GG1': stop(40, 15, (1800, 3000), 0, True), 'GG2': stop(25, 12, (1800, 3000), 0, True),
 'GG3': stop(50, 15, (1000, 2000), 0, True),
 'CH': affr(60, 110, (1800, 5500)), 'JH': affr(40, 90, (1800, 5500), .5),
}
assert set(A) == set(NAMES), set(NAMES) ^ set(A)

def reson(x, f, bw):
    """2-pole resonator, f may be an array (time-varying)"""
    f = np.broadcast_to(f, x.shape); y = np.zeros_like(x); y1 = y2 = 0.0
    c = -np.exp(-2 * np.pi * bw / FS); b = 2 * np.exp(-np.pi * bw / FS) * np.cos(2 * np.pi * f / FS); a = 1 - b - c
    for n in range(len(x)):
        y0 = a[n] * x[n] + b[n] * y1 + c * y2; y[n] = y0; y2, y1 = y1, y0
    return y
def bandnoise(n, lo, hi):
    X = np.fft.rfft(rng.standard_normal(n)); f = np.fft.rfftfreq(n, 1 / FS)
    X[(f < lo) | (f > hi)] = 0; x = np.fft.irfft(X, n); return x / (np.abs(x).max() + 1e-9)
def glottal(n, phase0=0.0):
    t = (np.arange(n) / FS * F0 + phase0) % 1.0
    g = np.where(t < .4, .5 - .5 * np.cos(np.pi * t / .4), np.where(t < .56, np.cos(np.pi * (t - .4) / .32), 0.0))
    return np.diff(g, prepend=0.0)                  # glottal flow derivative (includes lip radiation)
def formants(src, fa, fb, n):
    fa, fb = np.array(fa, float), np.array(fb, float); w = np.linspace(0, 1, n)[:, None]
    tr = fa + (fb - fa) * (3 * w ** 2 - 2 * w ** 3)        # smooth glide between the targets
    y = src
    for k in range(3): y = reson(y, tr[:, k], BW[k])
    return y
def env(n, att=.012, rel=.02):
    e = np.ones(n); a, r = max(1, int(att * FS)), max(1, int(rel * FS))
    e[:a] = np.linspace(0, 1, a); e[-r:] = np.minimum(e[-r:], np.linspace(1, 0, r)); return e
def ms(d): return int(round(d / 1000 * FS))

def synth(name):
    global rng
    rng = np.random.default_rng(1000 + NAMES.index(name))      # the same noise every build
    p = A[name]; n = ms(p['dur'])
    if p['k'] == 'pause': return np.zeros(n)
    if p['k'] == 'voice':
        y = formants(glottal(n), p['f0'], p['f1'], n)
        if p.get('nasal'): y = reson(y, 250, 100)   # nasal murmur: extra low pole
        return y / np.abs(y).max() * p['amp'] * env(n)
    if p['k'] == 'fric':
        y = bandnoise(n, *p['band']) * p['amp']
        if p['voiced']:
            v = formants(glottal(n), V['schwa'], V['schwa'], n); v = reson(v, 200, 150)
            y = y * (.6 + .4 * np.abs(np.sin(np.pi * np.arange(n) / FS * F0))) + v / np.abs(v).max() * p['voiced'] * .5
        return y * env(n, .015, .015)
    if p['k'] == 'hh':
        y = formants(rng.standard_normal(n), V['schwa'], V[p.get('glide', 'schwa')], n)
        return y / np.abs(y).max() * .5 * env(n, .01, .01)
    if p['k'] == 'stop':
        c, b, a = ms(p['clos']), ms(p['burst']), ms(p['asp'])
        clos = np.zeros(c)
        if p['voiced']: v = reson(reson(glottal(c), 180, 80), 180, 80); clos = v / (np.abs(v).max() + 1e-9) * .25
        burst = bandnoise(b, *p['band']) * p['amp'] * np.linspace(1, .4, b)
        asp = formants(rng.standard_normal(a), V['schwa'], V['schwa'], a) if a else np.zeros(0)
        if a: asp = asp / np.abs(asp).max() * .35 * np.linspace(1, 0, a)
        return np.concatenate([clos, burst, asp])
    if p['k'] == 'affr':
        c, f = ms(p['clos']), ms(p['fdur']); y = bandnoise(f, *p['band']) * .8 * env(f, .005, .02)
        if p['voiced']:
            v = formants(glottal(f), V['schwa'], V['schwa'], f); y = y + v / np.abs(v).max() * p['voiced'] * .5 * env(f)
        return np.concatenate([np.zeros(c), y])

def to_bits(x, gate=.06, pre=.9):
    """1 bit by infinite clipping of the pre-emphasised signal; quiet stretches hold the
    level (hysteresis), so pauses and closures are silent rather than hissing"""
    y = np.append(x[0], x[1:] - pre * x[:-1]) if pre else x
    peak = np.abs(y).max() + 1e-9; th = gate * peak; bits = np.zeros(len(y), np.uint8); s = 0
    for i, v in enumerate(y):
        if v > th: s = 1
        elif v < -th: s = 0
        bits[i] = s
    return bits
def pack(bits):
    n = (len(bits) + 7) // 8 * 8; b = np.zeros(n, np.uint8); b[:len(bits)] = bits
    if len(bits): b[len(bits):] = bits[-1]
    return np.packbits(b).tobytes()                 # MSB first: the player shifts left

def build_all():
    out = {}
    for name in NAMES:
        x = synth(name)
        out[name] = (len(x), b'' if A[name]['k'] == 'pause' else pack(to_bits(x)))
    return out

if __name__ == '__main__':
    d = build_all(); tot = sum(len(v[1]) for v in d.values())
    print('FS %.1f Hz; allophone data %d bytes; total time %.2f s' % (FS, tot, sum(v[0] for v in d.values()) / FS))

# ---- 1-bit coding: first-order delta-sigma at FS, cut into pitch-period frames.
# An allophone is a list of (repeat, frame_bits or None for silence).
HOP = {'voice': 3, 'hh': 2, 'fric': 2, 'stop': 1, 'affr': 1}
ORDER = 1
def dsm(x):
    """1-bit delta-sigma, error feedback with noise transfer (1 - z^-1)^ORDER"""
    q1 = q2 = 0.0; b = np.zeros(len(x), np.uint8)
    for i, v in enumerate(x):
        u = v - q1 if ORDER == 1 else v - 2 * q1 + q2
        o = 1.0 if u > 0 else -1.0; q2, q1 = q1, o - u; b[i] = o > 0
    return b
LEVEL = .8
DRIVE = 1.0                     # >0: RMS-normalise then soft-clip (tanh) to cut the crest factor
def shape(x, amp=1.0):
    if not DRIVE: return x * LEVEL
    r = np.sqrt(np.mean(x[np.abs(x) > .02 * np.abs(x).max()] ** 2)) + 1e-9
    return np.tanh(x / r * DRIVE) * LEVEL * amp
def frames(name, hop=None):
    p = A[name]; x = shape(synth(name), p.get('amp', 1.0) if p['k'] == 'voice' else min(1.0, 2 * p.get('amp', .5)))
    n = -(-len(x) // PERIOD) * PERIOD; x = np.append(x, np.zeros(n - len(x)))
    bits = dsm(x); hop = hop or (3 if p['k'] == 'voice' and p['f0'] == p['f1'] else HOP.get(p['k'], 1)); out = []
    for k in range(0, n // PERIOD, hop):
        seg = x[k * PERIOD:(k + 1) * PERIOD]; rep = min(hop, n // PERIOD - k)
        if np.abs(seg).max() < 0.02: fr = None
        else: fr = bits[k * PERIOD:(k + 1) * PERIOD]
        if out and fr is None and out[-1][1] is None: out[-1] = (out[-1][0] + rep, None)
        else: out.append((rep, fr))
    return out
def build_frames(hop=None):
    return {n: ([] if A[n]['k'] == 'pause' else frames(n, hop)) if A[n]['k'] != 'pause' else
            [(max(1, round(A[n]['dur'] / 1000 * F0)), None)] for n in NAMES}
def frames_bits(fr):
    return np.concatenate([np.tile(b, r) if b is not None else np.zeros(PERIOD * r, np.uint8) for r, b in fr]) if fr else np.zeros(0, np.uint8)
def frames_bytes(fr): return sum(1 + (37 if b is not None else 0) for r, b in fr) + 1
