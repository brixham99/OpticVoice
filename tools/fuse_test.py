#!/usr/bin/env python3
"""Real Fuse (SDL, OpticOS ROM build/opticos.rom from the OpticOS checkout):
LOAD "" the speech.tzx, let the program start, type 1, 2, 3 and some text, take
screenshots, and check the screen. (Fuse's sound is off: with SDL's disk audio driver
Fuse runs unthrottled and drops typed keys; the WAVs come from the rig, tools/test_play.py.) Usage: python3 tools/fuse_test.py"""
import os, sys, time, subprocess, wave
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..'))
REPO = os.environ.get('OPTICOS', '/workspace/opticos-repo')
sys.path.insert(0, os.path.join(REPO, 'tools')); sys.path.insert(0, os.path.join(REPO, 'tools', 'rig'))
from fuse_phase1 import Fuse, ENV, DATA, x, ensure_x
from fuse_phase2 import type_line
RAW = '/tmp/fuse_speech.raw'; OUT = os.path.join(ROOT, 'shots'); os.makedirs(OUT, exist_ok=True)
def launch():
    ensure_x(); env = dict(ENV)
    f = Fuse.__new__(Fuse)
    args = ['fuse-sdl', '--machine', '48', '--rom-48', os.path.join(REPO, 'build', 'opticos.rom'), '--no-auto-load',
            '--traps', '--fastload', '--no-sound', '--no-confirm-actions', '--no-statusbar',
            '--graphics-filter', 'normal', '--tape', os.path.join(ROOT, 'speech.tzx')]
    f.p = subprocess.Popen(args, env=env, cwd=DATA, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    for _ in range(50):
        time.sleep(0.2); w = x('xdotool', 'search', '--pid', str(f.p.pid)).split()
        if w: f.win = w[-1]; break
    time.sleep(1)
    g = dict(l.split('=') for l in x('xdotool', 'getwindowgeometry', '--shell', f.win).split())
    f.geo = int(g['X']), int(g['Y']), int(g['WIDTH']), int(g['HEIGHT'])
    x('xdotool', 'windowfocus', '--sync', f.win); x('xdotool', 'mousemove', '0', '0'); return f
if __name__ == '__main__':
    subprocess.run(['pkill', '-f', 'fuse-sdl.*opticos']); 
    if os.path.exists(RAW): os.remove(RAW)
    f = launch(); time.sleep(4.5)
    type_line(f, 'LOAD ""'); time.sleep(8)
    f.shot(os.path.join(OUT, 'fuse_menu.png'))
    marks = {}
    for k, wait in (('1', 3.0), ('2', 4.0), ('3', 4.0)):
        type_line(f, k); time.sleep(wait)
    type_line(f, 'Welcome to OpticOS.'); time.sleep(4)
    f.shot(os.path.join(OUT, 'fuse_spoken.png'))
    f.close(); print('saved', OUT)
