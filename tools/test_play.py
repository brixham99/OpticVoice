#!/usr/bin/env python3
"""Run the Z80 code (USR 45056: convert + say) in the OpticOS test rig with
the OpticOS ROM, record every edge of the speaker bit (port $FE bit 4) with
T-state timing, check the edges against the Python reference bit stream, and
write the recorded output as WAV (audio/*.wav).
Usage: python3 tools/test_play.py ["text" ...]"""
import os, sys, wave
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, '..'); sys.path.insert(0, HERE)
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo'); sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
import numpy as np
from scipy.signal import butter, sosfilt
from rig import Spectrum
import front, gen, synth
sym = gen.symbols(); code = open(os.path.join(ROOT, 'build', 'speech.bin'), 'rb').read()
CLOCK = 3_500_000
def new_spectrum():
    s = Spectrum(os.path.join(REPO, 'build', 'opticos.rom')); s.frame(200); s.load(gen.ORG, code); return s
def say(s, text):
    s.load(sym['textbuf'], text.encode('latin1') + b'\0')
    t0 = s_tstates(s); s.mic_start(4)
    r = s.call(gen.ORG, SP=0x6000, limit=400_000_000)
    return r['BC'], s.mic_pulses()
def s_tstates(s):
    import rig; return rig.lib.z_tstates()
def reference_runs(codes, F):
    """run lengths (in bits) of the reference level stream; silent frames hold the level"""
    lev = []; last = 0
    for c in codes:
        for rep, b in F[front.NAMES[c]]:
            if b is None: lev.append(np.full(synth.PERIOD * rep, last, np.uint8))
            else: t = np.tile(b, rep); lev.append(t); last = t[-1]
    x = np.concatenate(lev) if lev else np.zeros(1, np.uint8)
    edges = np.flatnonzero(np.diff(np.concatenate([[0], x])))       # starts at level 0
    return np.diff(edges)
def to_wav(pulses, path, fs=44100):
    t = np.cumsum(pulses).astype(np.int64)                           # edge times (T) from the start
    n = int(t[-1] / CLOCK * fs) + fs // 5
    # level as a function of time, box-averaged into output samples
    lev = np.zeros(n + 1); state = 0; prev = 0
    edges_s = t / CLOCK * fs
    acc = np.zeros(n + 2)
    # integrate: +1 where the level goes high, -1 where it goes low (alternating, first edge goes high)
    for k, e in enumerate(edges_s):
        i = int(e); f = e - i; sgn = 1 if k % 2 == 0 else -1
        acc[i] += sgn * (1 - f); acc[i + 1] += sgn * f
    y = np.cumsum(acc)[:n] * 2 - 1
    y = sosfilt(butter(2, 60, 'highpass', fs=fs, output='sos'), y)              # speaker: no DC
    y = sosfilt(butter(4, 6000, fs=fs, output='sos'), y)
    y = y / (np.abs(y).max() + 1e-9) * .85
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs); w.writeframes((y * 32767).astype('<i2').tobytes())
    return n / fs
if __name__ == '__main__':
    texts = sys.argv[1:] or ['HELLO NATHAN', 'OPTICA TECHNOLOGY DESIGN', 'I AM A ZX SPECTRUM']
    F = synth.build_frames(); g = front.load_rules(); s = new_spectrum(); fails = 0
    os.makedirs(os.path.join(ROOT, 'audio'), exist_ok=True)
    for text in texts:
        n, pulses = say(s, text); codes = front.to_allophones(text, g)
        ref = reference_runs(codes, F)
        # pulses[0] runs up to the first edge; if the speaker bit was left high (the start-up chime)
        # the player's first OUT is an extra edge, so try both alignments
        ok = n == len(codes) and abs(len(pulses) - 1 - len(ref)) <= 1; dev = np.array([99.0])
        for k in (1, 2):
            got = np.array(pulses[k:k + len(ref)], float) / synth.T_BIT
            if ok:
                m = min(len(got), len(ref)); d = np.abs(got[:m] - ref[:m])
                if np.mean(d < .6) > np.mean(dev < .6): dev = d
        # runs that cross a frame or allophone boundary also hold the level through the
        # player's housekeeping (up to ~700 T), so allow those few to be a little long
        okt = ok and np.mean(dev < 0.6) > 0.995 and dev.max() < 8
        fails += not okt
        name = ''.join(c for c in text.lower() if c.isalnum() or c == ' ').strip().replace(' ', '_')
        secs = to_wav(pulses, os.path.join(ROOT, 'audio', name + '.wav'))
        print('%-28s %2d allophones, %6d edges, %.2f s; edges match the reference: %s (%.2f%% exact to 0.6 bit, worst %.1f bits)' % (
            text, n, len(pulses), secs, 'PASS' if okt else 'FAIL', 100 * np.mean(dev < .6), dev.max()))
    sys.exit(1 if fails else 0)
