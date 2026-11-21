#!/usr/bin/env python3
"""Real Fuse 48K (SDL, OpticOS ROM build/opticos.rom from the OpticOS checkout): LOAD "" the
opticvoice.tzx (auto-runs: start-up lines, "OpticVoice ready.", Say? prompt), say typed text,
PITCH / TUNE commands, a preset, SPACE stopping a phrase, empty ENTER to quit, LIST; 3x
screenshots shots/ov_*.png and Fuse's own sound (SDL disk audio) to audio/ov_*.wav.
Usage: python3 tools/fuse_test.py"""
import os, sys, time, subprocess, wave, shutil
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..'))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
sys.path.insert(0, os.path.join(REPO, 'tools')); sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from fuse_phase1 import Fuse, ENV, DATA, DISP, x, ensure_x
from fuse_phase2 import type_line
RAW = '/tmp/fuse_speech.raw'; OUT = os.path.join(ROOT, 'shots'); os.makedirs(OUT, exist_ok=True)
def launch():
    ensure_x(); env = dict(ENV, SDL_AUDIODRIVER='disk', SDL_DISKAUDIOFILE=RAW, SDL_DISKAUDIODELAY='20')
    f = Fuse.__new__(Fuse)
    args = ['fuse-sdl', '--machine', '48', '--rom-48', os.path.join(REPO, 'build', 'opticos.rom'), '--no-auto-load',
            '--traps', '--fastload', '--sound', '--sound-freq', '44100', '--no-confirm-actions', '--no-statusbar',
            '--graphics-filter', 'normal', '--tape', os.path.join(ROOT, 'opticvoice.tzx')]
    f.p = subprocess.Popen(args, env=env, cwd=DATA, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    for _ in range(50):
        time.sleep(0.2); w = x('xdotool', 'search', '--pid', str(f.p.pid)).split()
        if w: f.win = w[-1]; break
    time.sleep(1)
    g = dict(l.split('=') for l in x('xdotool', 'getwindowgeometry', '--shell', f.win).split())
    f.geo = int(g['X']), int(g['Y']), int(g['WIDTH']), int(g['HEIGHT'])
    x('xdotool', 'windowfocus', '--sync', f.win); x('xdotool', 'mousemove', '0', '0'); return f
def size(): return os.path.getsize(RAW) if os.path.exists(RAW) else 0
def save_segment(raw, a, b, path):
    d = np.frombuffer(raw[a // 4 * 4:b // 4 * 4], np.int16).reshape(-1, 2)[:, 0].astype(float)
    n = 2205; e = np.array([np.abs(np.diff(d[i:i + n])).mean() for i in range(0, len(d) - n, n)])
    act = np.flatnonzero(e > 50)
    if not len(act): return 0
    d = d[max(0, (act[0] - 4) * n):(act[-1] + 6) * n]; d -= d.mean(); d = d / (np.abs(d).max() + 1e-9) * .9
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100); w.writeframes((d * 32767).astype('<i2').tobytes())
    return len(d) / 44100
def shot3(f, name):
    """a screen grab at 3x (960 x 720), nearest-neighbour"""
    X, Y, W, H = f.geo
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'x11grab', '-video_size', '%dx%d' % (W, H),
                    '-i', '%s+%d,%d' % (DISP, X, Y), '-frames:v', '1',
                    '-vf', 'scale=iw*3:ih*3:flags=neighbor', os.path.join(OUT, name)], env=ENV)
def keys_only(f, text):
    from fuse_phase2 import SYM
    for ch in text:
        if ch == ' ': f.key('space')
        elif ch in SYM: f.key(SYM[ch], mods=('Control_L',))
        elif ch.isupper(): f.key(ch.lower(), mods=('Shift_L',))
        else: f.key(ch)
if __name__ == '__main__':
    subprocess.run(['pkill', '-f', 'fuse-sdl.*opticos'])
    if os.path.exists(RAW): os.remove(RAW)
    f = launch(); time.sleep(4.5)
    keys_only(f, 'LOAD ""'); time.sleep(0.3); a0 = size(); f.key('Return'); time.sleep(10)
    marks = {'ready': (a0, size())}; shot3(f, 'ov_start.png')
    def say(tag, line, wait):
        a = size(); type_line(f, line); time.sleep(wait); marks[tag] = (a, size())
    keys_only(f, 'Hello Nathan, are you ready?'); time.sleep(0.4); shot3(f, 'ov_typing.png')
    a = size(); f.key('Return'); time.sleep(3.5); marks['question'] = (a, size())
    say('welcome', 'Welcome to OpticVoice.', 3.0); shot3(f, 'ov_spoken.png')
    type_line(f, 'PITCH 30'); time.sleep(0.8); say('high', 'Hello Nathan.', 2.5)
    type_line(f, 'TUNE OFF'); time.sleep(0.8); say('monotone', 'Are you ready?', 2.5)
    type_line(f, 'TUNE ON'); time.sleep(0.8); type_line(f, 'PITCH 37'); time.sleep(0.8)
    type_line(f, '4'); time.sleep(0.8); x('xdotool', 'keydown', '--window', f.win, 'space'); time.sleep(0.4)
    x('xdotool', 'keyup', '--window', f.win, 'space'); time.sleep(6)
    type_line(f, ''); time.sleep(1.5); shot3(f, 'ov_quit.png')
    shutil.copy(RAW, RAW + '.copy'); f.close(); raw = open(RAW + '.copy', 'rb').read()
    for tag in marks:
        a, b = marks[tag]; print(tag, '%.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'ov_%s.wav' % tag)))
