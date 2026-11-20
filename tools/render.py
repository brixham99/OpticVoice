#!/usr/bin/env python3
"""Render phrases from the 1-bit allophone data exactly as the Z80 player plays
them (whole bytes per allophone), to WAV; and score them with vosk if present."""
import os, sys, json, wave, numpy as np
from scipy.signal import resample_poly, butter, sosfilt
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import front, synth
def phrase_bits(codes, data):
    out = []
    for c in codes:
        n, b = data[front.NAMES[c]]
        out.append(np.zeros(n, np.uint8) + (out[-1][-1] if out and len(out[-1]) else 0) if not b else
                   np.unpackbits(np.frombuffer(b, np.uint8)))
    return np.concatenate(out) if out else np.zeros(0, np.uint8)
def bits_to_audio(bits, fs_in=synth.FS, fs_out=16000):
    x = bits.astype(float) * 2 - 1; x -= x.mean()          # the speaker's DC block
    up = np.repeat(x, 8)                                    # hold each level (fs*8 = 62.5 kHz)
    sos = butter(4, 5000, fs=fs_in * 8, output='sos'); y = sosfilt(sos, up)
    from fractions import Fraction
    r = Fraction(fs_out, int(fs_in * 8 * 2)).limit_denominator(1000)   # fs_in*8 = 62500
    y = resample_poly(y, r.numerator * 2, r.denominator) if False else resample_poly(y, 32, 125)
    return (y / (np.abs(y).max() + 1e-9) * .8).astype(np.float32)
def write_wav(path, y, fs=16000):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype('<i2').tobytes())
_model = None
def recognise(path):
    global _model
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
    if _model is None: _model = Model(os.path.join(HERE, '..', 'ref', 'vosk', 'vosk-model-small-en-us-0.15'))
    r = KaldiRecognizer(_model, 16000); wf = wave.open(path, 'rb')
    while True:
        d = wf.readframes(4000)
        if not d: break
        r.AcceptWaveform(d)
    return json.loads(r.FinalResult())['text']
PHRASES = ['HELLO NATHAN', 'OPTICA TECHNOLOGY DESIGN', 'I AM A ZX SPECTRUM', 'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG',
           'ONE TWO THREE FOUR FIVE', 'GOOD MORNING', 'THIS IS A TEST', 'WELCOME TO OPTICOS']
if __name__ == '__main__':
    g = front.load_rules(); data = synth.build_all(); os.makedirs('/tmp/sp', exist_ok=True)
    for i, p in enumerate(PHRASES):
        f = '/tmp/sp/p%d.wav' % i; write_wav(f, bits_to_audio(phrase_bits(front.to_allophones(p, g), data)))
        try: print('%-45s -> %s' % (p, recognise(f)))
        except Exception as e: print(p, 'no vosk', e); break
