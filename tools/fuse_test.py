#!/usr/bin/env python3
"""Real Fuse (SDL, OpticOS ROM build/opticos.rom from the OpticOS checkout): LOAD "" the
speech.tzx, let the program start, say presets 1 and 5, change pitch (P) and intonation
(M), say typed text, stop a long phrase with SPACE, take screenshots (shots/), and record
Fuse's own sound output (SDL disk audio, throttled to real time with SDL_DISKAUDIODELAY)
to audio/fuse_*.wav. Usage: python3 tools/fuse_test.py"""
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
            '--graphics-filter', 'normal', '--tape', os.path.join(ROOT, 'speech.tzx')]
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
    f = launch(); time.sleep(4.5); shot3(f, 'fuse_boot.png')
    keys_only(f, 'LOAD ""'); time.sleep(0.5); shot3(f, 'fuse_load.png'); f.key('Return'); time.sleep(8)
    shot3(f, 'fuse_menu.png'); time.sleep(1.0)
    marks = {}
    for k, wait in (('1', 3.0), ('5', 4.5)):
        a = size(); type_line(f, k); time.sleep(wait); marks.setdefault(k, []).append((a, size()))
    keys_only(f, 'Welcome to OpticOS.'); time.sleep(0.5); shot3(f, 'fuse_typing.png')
    f.key('Return'); time.sleep(4.0); shot3(f, 'fuse_spoken.png')
    for k, wait in (('p', 1.0), ('p', 1.0), ('Are you ready?', 3.5), ('m', 1.0), ('Are you ready?', 3.5), ('m', 1.0), ('p', 1.0), ('p', 1.0)):
        a = size(); type_line(f, k); time.sleep(wait); marks.setdefault(k, []).append((a, size()))
    type_line(f, '4'); time.sleep(0.8); x('xdotool', 'keydown', '--window', f.win, 'space'); time.sleep(0.4)
    x('xdotool', 'keyup', '--window', f.win, 'space'); time.sleep(7)
    shot3(f, 'fuse_stopped.png')
    type_line(f, ''); time.sleep(1.0); type_line(f, 'LIST'); time.sleep(2.0); shot3(f, 'fuse_listing.png')
    shutil.copy(RAW, RAW + '.copy'); f.close(); raw = open(RAW + '.copy', 'rb').read()
    for key, name in (('1', 'fuse_hello_nathan.wav'), ('5', 'fuse_question.wav')):
        a, b = marks[key][0]; print(name, '%.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', name)))
    a, b = marks['Are you ready?'][0]; print('fuse_high_pitch.wav %.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'fuse_high_pitch.wav')))
    a, b = marks['Are you ready?'][1]; print('fuse_monotone.wav %.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'fuse_monotone.wav')))
    print('saved', OUT)
