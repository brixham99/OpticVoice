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
B128 = os.environ.get('BUILD') == '128'
NAME = 'speech128' if B128 else 'speech'; BASE = gen.ORG128 if B128 else gen.ORG
sym = gen.symbols(NAME); code = open(os.path.join(ROOT, 'build', NAME + '.bin'), 'rb').read()
BANK4 = open(os.path.join(ROOT, 'build', 'bank4.bin'), 'rb').read() if B128 else b''   # the rig ignores $7FFD: bank 4 'is' $C000
CLOCK = 3_500_000
LIMIT = [400_000_000]
def new_spectrum():
    s = Spectrum(os.path.join(REPO, 'build', 'opticos.rom')); s.frame(200); s.load(BASE, code); s.load(0xC000, BANK4); return s
def say(s, text):
    s.load(sym['textbuf'], text.encode('latin1') + b'\0')
    t0 = s_tstates(s); s.mic_start(4)
    r = s.call(BASE, SP=0x6000, limit=LIMIT[0])
    return r['BC'], s.mic_pulses()
BANKS = {b: open(os.path.join(ROOT, 'build', 'bank%d.bin' % b), 'rb').read() for b in (4, 6, 1, 3)} if B128 else {}
def say_paged(s, text):
    """say() with $7FFD paging emulated: at al_pg (just after the OUT) copy the paged bank to $C000"""
    s.load(sym['textbuf'], text.encode('latin1') + b'\0'); s.load(0x5FF0, b'\x18\xfe')
    s.poke(0x5FFE, 0xF0); s.poke(0x5FFF, 0x5F); s.setregs(PC=BASE, SP=0x5FFE); left = LIMIT[0]; pages = 0
    while True:
        t = s_tstates(s); r = s.run_until2(sym['al_pg'], 0x5FF0, left); left -= s_tstates(s) - t
        if r == 0: raise TimeoutError('AY say did not return')
        if r == 2: return s.regs()['BC'], pages
        bank = s.regs()['AF'] >> 8 & 7; s.load(0xC000, BANKS.get(bank, bytes(16384))); pages += 1
        s.run_until(0x1FFFF, 1)                        # step off the label
def s_tstates(s):
    import rig; return rig.lib.z_tstates()
def reference_runs(codes, F, pitch=synth.NBYTE):
    """run lengths (in bits) of the reference level stream (synth.play_bits: pitch levels,
    pads, silent frames holding the level)"""
    x = synth.play_bits(codes, F, pitch) if codes else np.zeros(1, np.uint8)
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
        ok = n == len(codes) and abs(len(pulses) - 1 - len(ref)) <= 3; dev = np.array([99.0])
        tot = 9.0
        for k in (1, 2, 3):
            got = np.array(pulses[k:k + len(ref)], float) / synth.T_BIT
            if ok:
                m = min(len(got), len(ref)); d = np.abs(got[:m] - ref[:m])
                if np.mean(d < .6) > np.mean(dev < .6): dev = d; tot = got[:m].sum() / ref[:m].sum()
        # runs that cross a frame or allophone boundary also hold the level through the
        # player's housekeeping (~300 T a period, ~1,200 T an allophone), so allow those few
        # to be a little long; the total time must be within 1.5% of the reference
        okt = ok and np.mean(dev < 0.6) > 0.99 and dev.max() < 16 and abs(tot - 1) < 0.015
        fails += not okt
        name = ''.join(c for c in text.lower() if c.isalnum() or c == ' ').strip().replace(' ', '_')
        secs = to_wav(pulses, os.path.join(ROOT, 'audio', name + '.wav'))
        print('%-28s %2d allophones, %6d edges, %.2f s; edges match the reference: %s (%.2f%% exact to 0.6 bit, worst %.1f bits, time %+.2f%%)' % (
            text, n, len(pulses), secs, 'PASS' if okt else 'FAIL', 100 * np.mean(dev < .6), dev.max(), 100 * (tot - 1)))
    # SPACE held: the speech stops before the next allophone, STOPPED (45075) = 1
    # (the player then waits for SPACE to be let go before it returns, so BASIC never sees the key)
    s.key(' '); LIMIT[0] = 20_000_000
    try: say(s, 'This sentence should not be heard'); waited = False
    except TimeoutError: waited = True
    LIMIT[0] = 400_000_000; s.key(' ', False); back = s.run_until(0x5FF0, 10_000_000); pulses = s.mic_pulses()
    stopped = s.peek(sym['STOPPED']); t = sum(pulses) / CLOCK
    okb = waited and back and stopped == 1 and t < 0.05; fails += not okb
    print('SPACE held: STOPPED=%d, %d edges, %.3f s of output, waits for release then returns: %s' % (
        stopped, len(pulses), t, 'PASS' if okb else 'FAIL'))
    if B128:   # the AY player in the rig: no AY there, but it must run and take the model's time
        s.load(sym['DEVICE'], b'\x01')
        for text in texts[:3]:
            import rig; t0 = rig.lib.z_tstates(); n, pg = say_paged(s, text); dt = rig.lib.z_tstates() - t0
            s.load(sym['textbuf'], text.encode('latin1') + b'\0'); t1 = rig.lib.z_tstates(); s.call(BASE + 6, SP=0x6000, limit=LIMIT[0])
            dt -= rig.lib.z_tstates() - t1               # minus the text conversion (same code as the beeper path)
            want = len(synth.play_ay(front.to_allophones(text, g))) * synth.T_AY
            ok = abs(dt / want - 1) < 0.05; fails += not ok
            print('AY %-26s %2d allophones, %.3f s playing (conversion excluded) vs %.3f s model (%+.2f%%): %s' % (text, n, dt / CLOCK, want / CLOCK, 100 * (dt / want - 1), 'PASS' if ok else 'FAIL'))
        s.load(sym['DEVICE'], b'\x00'); s.load(0xC000, BANK4)
    n, pulses = say(s, 'Go'); okb = s.peek(sym['STOPPED']) == 0 and len(pulses) > 100; fails += not okb
    print('after release: speaks again, STOPPED=%d: %s' % (s.peek(sym['STOPPED']), 'PASS' if okb else 'FAIL'))
    sys.exit(1 if fails else 0)
