#!/usr/bin/env python3
"""Intelligibility check: render test phrases from the 1-bit allophone data exactly as
the Z80 player plays them, filter like a speaker (60 Hz - 5 kHz), and score them with
automatic recognisers (vosk small-en; Whisper base.en if installed) as word error rate.
Usage: python3 tools/evaluate.py [--tools DIR] [--mode bits|float] [--wav DIR] [--asr vosk,whisper]"""
import os, sys, json, wave, argparse, re, numpy as np
from scipy.signal import butter, sosfiltfilt, resample_poly
HERE = os.path.dirname(os.path.abspath(__file__))
VOSK = os.path.join(HERE, '..', 'ref', 'vosk', 'vosk-model-small-en-us-0.15')
PHRASES = ['HELLO NATHAN', 'OPTICA TECHNOLOGY DESIGN', 'I AM A ZX SPECTRUM', 'WELCOME TO OPTICOS',
           'ONE TWO THREE FOUR FIVE', 'SIX SEVEN EIGHT NINE TEN', 'GOOD MORNING', 'THIS IS A TEST',
           'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG', 'PLEASE PRESS ANY KEY', 'GAME OVER',
           'THE BIRCH CANOE SLID ON THE SMOOTH PLANKS', 'GLUE THE SHEET TO THE DARK BLUE BACKGROUND',
           'IT IS EASY TO TELL THE DEPTH OF A WELL', 'THESE DAYS A CHICKEN LEG IS A RARE DISH',
           'RICE IS OFTEN SERVED IN ROUND BOWLS', 'THE JUICE OF LEMONS MAKES FINE PUNCH',
           'WHAT TIME IS IT', 'ARE YOU READY', 'WE LIKE TO PLAY GAMES ON THE COMPUTER']
HELD = ['PLEASE INSERT THE TAPE', 'LOADING COMPLETE', 'THE WEATHER IS NICE TODAY', 'I LIKE GREEN APPLES',
        'WHERE IS THE STATION', 'HOW ARE YOU', 'THE CAT SAT ON THE MAT', 'TURN LEFT AT THE NEXT ROAD',
        'MY NAME IS NATHAN', 'PLAY IT AGAIN', 'THE BATTERY IS LOW', 'OPEN THE DOOR PLEASE']   # held out: not used for tuning
DIG = dict(zip('0123456789', 'zero one two three four five six seven eight nine'.split()))
def norm(t):
    t = t.lower().replace('-', ' ')
    t = re.sub(r'\d', lambda m: ' ' + DIG[m.group()] + ' ', t)
    return re.sub(r"[^a-z' ]", ' ', t).split()
def wer(ref, hyp):
    r, h = norm(ref), norm(hyp); d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (r[i - 1] != h[j - 1]))
    return d[len(h)], len(r)
def hits(ref, hyp):
    """reference words recognised, in order (longest common subsequence)"""
    r, h = norm(ref), norm(hyp); d = [0] * (len(h) + 1)
    for i in range(len(r)):
        p = 0
        for j in range(len(h)):
            p, d[j + 1] = d[j + 1], p + 1 if r[i] == h[j] else max(d[j + 1], d[j])
    return d[len(h)]
def to_audio(x, fs):
    """x: 0/1 bits or float at fs -> 16 kHz float, speaker-like band"""
    x = np.asarray(x, float)
    if x.max() <= 1 and x.min() >= 0 and set(np.unique(x)) <= {0., 1.}: x = x * 2 - 1
    x = np.concatenate([np.zeros(int(.3 * fs)), x - x.mean(), np.zeros(int(.3 * fs))])
    x = sosfiltfilt(butter(2, [60, 5000], 'bandpass', fs=fs, output='sos'), x)
    from fractions import Fraction
    f = Fraction(16000, int(round(fs))).limit_denominator(2000); y = resample_poly(x, f.numerator, f.denominator)
    return (y / (np.abs(y).max() + 1e-9) * .8).astype(np.float32)
def write_wav(path, y, fs=16000):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype('<i2').tobytes())
_m = {}
def vosk_text(y):
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
    if 'v' not in _m: _m['v'] = Model(VOSK)
    r = KaldiRecognizer(_m['v'], 16000); r.AcceptWaveform((np.clip(y, -1, 1) * 32767).astype('<i2').tobytes())
    return json.loads(r.FinalResult())['text']
def whisper_text(y):
    import whisper
    if 'w' not in _m: _m['w'] = whisper.load_model('base.en')
    return _m['w'].transcribe(y, language='en', fp16=False, temperature=0, condition_on_previous_text=False)['text']
ASR = {'vosk': vosk_text, 'whisper': whisper_text}
def render(text, mode='bits'):
    import front, synth
    codes = front.to_allophones(text, front.load_rules())
    if mode == 'ay': return synth.play_ay(codes), synth.FS_AY
    if hasattr(synth, 'render_codes'): return synth.render_codes(codes, mode), synth.FS
    if mode == 'float':
        return np.concatenate([synth.shape(synth.synth(front.NAMES[c])) if synth.A[front.NAMES[c]]['k'] != 'pause'
                               else np.zeros(synth.ms(synth.A[front.NAMES[c]]['dur'])) for c in codes]), synth.FS
    F = render.F = getattr(render, 'F', None) or synth.build_frames()
    return np.concatenate([synth.frames_bits(F[front.NAMES[c]]) for c in codes]), synth.FS
def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--tools', default=HERE); ap.add_argument('--mode', default='bits')
    ap.add_argument('--wav'); ap.add_argument('--asr', default='vosk'); ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--set', default='main'); ap.add_argument('--json'); a = ap.parse_args()
    a.json = a.json and os.path.abspath(a.json); a.wav = a.wav and os.path.abspath(a.wav)
    sys.path.insert(0, os.path.abspath(a.tools)); os.chdir(os.path.abspath(a.tools))
    tot = {k: [0, 0, 0] for k in a.asr.split(',')}; rows = []
    if a.wav: os.makedirs(a.wav, exist_ok=True)
    for i, p in enumerate(HELD if a.set == 'held' else PHRASES):
        x, fs = render(p, a.mode); y = to_audio(x, fs)
        if a.wav: write_wav(os.path.join(a.wav, '%02d_%s.wav' % (i, p.lower().replace(' ', '_')[:30])), y)
        row = {'text': p}
        for k in tot:
            t = ASR[k](y); e, n = wer(p, t); tot[k][0] += e; tot[k][1] += n; tot[k][2] += hits(p, t); row[k] = t
            if not a.quiet: print('%-7s %-45s -> %s' % (k, p, t), flush=True)
        rows.append(row)
    res = {k: dict(words=v[1], correct=v[2], pct_correct=round(100 * v[2] / v[1], 1), wer=round(v[0] / v[1], 3)) for k, v in tot.items()}
    print(json.dumps(res))
    if a.json: json.dump(dict(summary=res, rows=rows), open(a.json, 'w'), indent=1)
if __name__ == '__main__': main()
