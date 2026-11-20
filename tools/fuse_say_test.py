#!/usr/bin/env python3
"""Real Fuse, 128K machine, OpticOS 128: the OpticOS ROM (branch opticos128-say, with the
extension hook) in ROM slot 0 and the SAY extension ROM (build/opticos128ext.rom) in slot 1.
No Sinclair ROM. LOAD "" say128.tzx (the banks), then typed SAY lines; 3x screenshots
shots/say_*.png and Fuse's sound to audio/say_*.wav. Also checks that an unknown name still
gives "No such PROC or FN" (here, and in a 48K and a two-OpticOS 128K: MODE=48 / MODE=plain).
Usage: python3 tools/fuse_say_test.py"""
import os, sys, time, subprocess, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from fuse_test import ENV, DATA, x, ensure_x, Fuse, type_line, shot3, keys_only, size, save_segment, RAW, ROOT, REPO
MODE = os.environ.get('MODE', 'ext')
def launch():
    ensure_x(); env = dict(ENV, SDL_AUDIODRIVER='disk', SDL_DISKAUDIOFILE=RAW, SDL_DISKAUDIODELAY='20')
    rom = os.path.join(REPO, 'build', 'opticos.rom'); ext = os.path.join(ROOT, 'build', 'opticos128ext.rom')
    m = {'ext': ['--machine', '128', '--rom-128-0', rom, '--rom-128-1', ext],
         'plain': ['--machine', '128', '--rom-128-0', rom, '--rom-128-1', rom],
         '48': ['--machine', '48', '--rom-48', rom]}[MODE]
    f = Fuse.__new__(Fuse)
    args = ['fuse-sdl'] + m + ['--no-auto-load', '--traps', '--fastload', '--sound', '--sound-freq', '44100',
            '--no-confirm-actions', '--no-statusbar', '--graphics-filter', 'normal', '--tape', os.path.join(ROOT, 'say128.tzx')]
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
    f = launch(); time.sleep(4.5)
    if MODE != 'ext':
        type_line(f, 'SAY "HELLO NATHAN"'); time.sleep(1.5); type_line(f, 'foo'); time.sleep(1.0)
        shot3(f, 'say_%s_noproc.png' % MODE); f.close(); sys.exit()
    shot3(f, 'say_boot.png')
    type_line(f, 'SAY "HELLO NATHAN"'); time.sleep(1.5); shot3(f, 'say_nodata.png')
    keys_only(f, 'LOAD ""'); time.sleep(0.3); f.key('Return')
    time.sleep(float(os.environ.get('LOADWAIT', '45'))); shot3(f, 'say_loaded.png')
    marks = {}
    def say(tag, line, wait):
        a = size(); type_line(f, line); time.sleep(wait); marks[tag] = (a, size())
    keys_only(f, 'SAY "HELLO NATHAN"'); time.sleep(0.5); shot3(f, 'say_typing.png'); a = size(); f.key('Return'); time.sleep(3.0); marks['hello'] = (a, size())
    say('question', 'greet "Nathan"', 4.5)
    say('optica', 'SAY "Optica Technology Design."', 4.0)
    type_line(f, 'SAY VOICE BUZZER'); time.sleep(0.8)
    say('buzzer', 'SAY "HELLO NATHAN"', 3.0)
    type_line(f, 'SAY VOICE AY'); time.sleep(0.8); type_line(f, 'SAY PITCH 30'); time.sleep(0.8)
    say('high', 'SAY "HELLO NATHAN"', 3.0)
    type_line(f, 'SAY PITCH 37'); time.sleep(0.8)
    type_line(f, 'foo'); time.sleep(1.0); shot3(f, 'say_spoken.png')
    type_line(f, 'CLS'); time.sleep(0.5); type_line(f, 'LIST greet'); time.sleep(1.5); shot3(f, 'say_listing.png')
    shutil.copy(RAW, RAW + '.copy'); f.close(); raw = open(RAW + '.copy', 'rb').read()
    for tag in marks:
        a, b = marks[tag]; print(tag, '%.2f s' % save_segment(raw, a, b, os.path.join(ROOT, 'audio', 'say_%s.wav' % tag)))
