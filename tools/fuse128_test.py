#!/usr/bin/env python3
"""Real Fuse, 128K machine, with the OpticOS ROM in both ROM slots (no Sinclair ROM):
OUT 32765,16 (so the ROM-1 slot is paged and Fuse's tape traps apply), LOAD "" the
speech128.tzx (program, resident code, banks 4, 6, 1, 3), say presets with the AY chip
and with the beeper (D toggles), take 3x screenshots (shots/fuse128_*.png) and record
Fuse's own sound (SDL disk audio) to audio/fuse128_*.wav. Usage: python3 tools/fuse128_test.py"""
import os, sys, time, subprocess, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import fuse_test as ft
from fuse_test import ENV, DATA, x, ensure_x, Fuse, type_line, shot3, keys_only, size, save_segment, RAW, ROOT, REPO
def launch():
    ensure_x(); env = dict(ENV, SDL_AUDIODRIVER='disk', SDL_DISKAUDIOFILE=RAW, SDL_DISKAUDIODELAY='20')
    rom = os.path.join(REPO, 'build', 'opticos.rom'); f = Fuse.__new__(Fuse)
    args = ['fuse-sdl', '--machine', '128', '--rom-128-0', rom, '--rom-128-1', rom, '--no-auto-load',
            '--traps', '--fastload', '--sound', '--sound-freq', '44100', '--no-confirm-actions', '--no-statusbar',
            '--graphics-filter', 'normal', '--tape', os.path.join(ROOT, 'speech128.tzx')]
    f.p = subprocess.Popen(args, env=env, cwd=DATA, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    for _ in range(50):
        time.sleep(0.2); w = x('xdotool', 'search', '--pid', str(f.p.pid)).split()
        if w: f.win = w[-1]; break
    time.sleep(1)
    g = dict(l.split('=') for l in x('xdotool', 'getwindowgeometry', '--shell', f.win).split())
    f.geo = int(g['X']), int(g['Y']), int(g['WIDTH']), int(g['HEIGHT'])
    x('xdotool', 'windowfocus', '--sync', f.win); x('xdotool', 'mousemove', '0', '0'); return f
if __name__ == '__main__':
    subprocess.run(['pkill', '-f', 'fuse-sdl.*opticos'])
    if os.path.exists(RAW): os.remove(RAW)
    f = launch(); time.sleep(4.5); shot3(f, 'fuse128_boot.png')
    type_line(f, 'OUT 32765,16'); time.sleep(0.5)
    keys_only(f, 'LOAD ""'); time.sleep(0.5); shot3(f, 'fuse128_load.png'); f.key('Return')
    time.sleep(float(os.environ.get('LOADWAIT', '20'))); shot3(f, 'fuse128_menu.png'); time.sleep(1.0)
    marks = {}
    def say(tag, k, wait):
        a = size(); type_line(f, k); time.sleep(wait); marks[tag] = (a, size())
    say('ay_1', '1', 3.0); say('ay_2', '2', 4.0); say('ay_3', '3', 3.5); say('ay_5', '5', 4.5)
    shot3(f, 'fuse128_ay_spoken.png')
    keys_only(f, 'Welcome to OpticOS.'); time.sleep(0.5); shot3(f, 'fuse128_typing.png')
    a = size(); f.key('Return'); time.sleep(4.0); marks['ay_welcome'] = (a, size())
    type_line(f, 'd'); time.sleep(1.0)
    say('bp_1', '1', 3.0); say('bp_5', '5', 4.5); shot3(f, 'fuse128_beeper.png')
    type_line(f, 'd'); time.sleep(1.0); shot3(f, 'fuse128_device.png')
    shutil.copy(RAW, RAW + '.copy'); f.close(); raw = open(RAW + '.copy', 'rb').read()
    for tag in marks:
        a, b = marks[tag]; print(tag, '%.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'fuse128_%s.wav' % tag)))
