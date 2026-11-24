#!/usr/bin/env python3
"""Real Fuse 48K with the standard Sinclair 48K ROM (supply your own: ROM48=/path/48.rom; never
committed): LOAD "" opticvoice48rom.tzx, then every command path: start-up lines and "OpticVoice
ready.", typed text, PITCH, TUNE OFF/ON, presets 1-5, HELP, SPACE stop, BREAK during speech,
BREAK out of Say? and free memory, ENTER on its own to quit.
3x grabs shots/ovr_*.png, Fuse's own sound to audio/ovr_*.wav."""
import os, sys, time, subprocess, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
import fuse_test as ft
from fuse_test import keys_only, shot3, size, save_segment, RAW, x
from fuse_phase1 import Fuse, ENV, DATA, ensure_x
from fuse_phase2 import type_line
ROM48 = os.environ.get('ROM48', '/workspace/ultimate/roms/48.rom')
def launch():
    ensure_x(); env = dict(ENV, SDL_AUDIODRIVER='disk', SDL_DISKAUDIOFILE=RAW, SDL_DISKAUDIODELAY='20')
    f = Fuse.__new__(Fuse)
    args = ['fuse-sdl', '--machine', '48', '--rom-48', ROM48, '--no-auto-load', '--traps', '--fastload', '--sound',
            '--sound-freq', '44100', '--no-confirm-actions', '--no-statusbar', '--graphics-filter', 'normal',
            '--tape', os.path.join(ROOT, 'opticvoice48rom.tzx')]
    f.p = subprocess.Popen(args, env=env, cwd=DATA, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    for _ in range(50):
        time.sleep(0.2); w = x('xdotool', 'search', '--pid', str(f.p.pid)).split()
        if w: f.win = w[-1]; break
    time.sleep(1)
    g = dict(l.split('=') for l in x('xdotool', 'getwindowgeometry', '--shell', f.win).split())
    f.geo = int(g['X']), int(g['Y']), int(g['WIDTH']), int(g['HEIGHT'])
    x('xdotool', 'windowfocus', '--sync', f.win); x('xdotool', 'mousemove', '0', '0'); return f
def ext(f, k):                      # extended mode (CAPS + SYMBOL together), then a key
    f.key('Shift_L', mods=('Control_L',)); f.key(k)
def hold(f, keys, t):
    for k in keys: x('xdotool', 'keydown', '--window', f.win, k)
    time.sleep(t)
    for k in reversed(keys): x('xdotool', 'keyup', '--window', f.win, k)
if __name__ == '__main__':
    subprocess.run(['pkill', '-f', 'fuse-sdl'])
    if os.path.exists(RAW): os.remove(RAW)
    f = launch(); time.sleep(3.5)
    f.key('j'); keys_only(f, '""'); time.sleep(0.3); a0 = size(); f.key('Return'); time.sleep(11)
    marks = {'ready': (a0, size())}; shot3(f, 'ovr_start.png')
    def say(tag, line, wait):
        a = size(); type_line(f, line); time.sleep(wait); marks[tag] = (a, size())
    say('question', 'Hello Nathan, are you ready?', 3.5)
    say('welcome', 'Welcome to OpticVoice.', 3.0); shot3(f, 'ovr_spoken.png')
    type_line(f, 'PITCH 30'); time.sleep(0.8); say('high', 'Hello Nathan.', 2.5)
    type_line(f, 'pitch 99'); time.sleep(0.8)
    type_line(f, 'TUNE OFF'); time.sleep(0.8); say('monotone', 'Are you ready?', 2.5)
    type_line(f, 'tune on'); time.sleep(0.8); type_line(f, 'PITCH 37'); time.sleep(0.8)
    for p in '1235': say('preset%s' % p, p, 3.5)
    type_line(f, 'HELP'); time.sleep(1.0); shot3(f, 'ovr_commands.png')
    type_line(f, '4'); time.sleep(0.8); hold(f, ['space'], 0.4); time.sleep(6); shot3(f, 'ovr_space.png')
    type_line(f, '3'); time.sleep(0.6); hold(f, ['Shift_L', 'space'], 0.6); time.sleep(1.5); shot3(f, 'ovr_break.png')
    f.key('6', mods=('Shift_L',)); time.sleep(1.0)    # CAPS SHIFT + 6 at Say?: H STOP in INPUT
    shot3(f, 'ovr_inputbreak.png')
    f.key('p'); ext(f, 'o'); keys_only(f, '23730+256*'); ext(f, 'o'); keys_only(f, '23731-'); ext(f, 'o')
    keys_only(f, '23653-256*'); ext(f, 'o'); keys_only(f, '23654'); f.key('Return'); time.sleep(1.0)
    f.key('p'); keys_only(f, '65535-'); ext(f, 'l'); keys_only(f, '7962'); f.key('Return'); time.sleep(1.0)
    shot3(f, 'ovr_free.png')
    f.key('g'); keys_only(f, '60'); f.key('Return'); time.sleep(1.0); f.key('Return'); time.sleep(1.5)  # GO TO 60, ENTER quits
    shot3(f, 'ovr_quit.png')
    f.key('r'); f.key('Return'); time.sleep(9); shot3(f, 'ovr_rerun.png')   # RUN again: code not reloaded
    shutil.copy(RAW, RAW + '.copy'); f.close(); raw = open(RAW + '.copy', 'rb').read()
    for tag in marks:
        a, b = marks[tag]; print(tag, '%.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'ovr_%s.wav' % tag)))
