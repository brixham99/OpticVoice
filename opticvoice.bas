' ===========================================================
' OpticVoice 1.1 - text to speech for OpticOS (48K, beeper)
' (c) 2026 Optica Technology Design. MIT licence (code).
' LOAD "" runs it. The machine code block "ovcode"
' (CODE 45056,...) does the work; it is not reloaded if
' it is already in memory:
'   n = USR 45056  say the text in the text buffer
'   n = USR 45059  say the allophone list at DPEEK(45067)
'   n = USR 45062  convert only: list at DPEEK(45069)
' POKE the text at DPEEK(45071), then a 0. n is the number
' of allophones. SPACE stops it (PEEK 45075 = 1 if so).
' POKE 45076 = pitch (37 normal, smaller is higher),
' POKE 45077,0 = monotone, POKE 45078,0 = no variants.
' ===========================================================
CLEAR 45055
IF PEEK(45073) <> 83 OR PEEK(45074) <> 80 OR PEEK(45079) <> 3 THEN LOAD "ovcode" CODE
title
say "OpticVoice ready."
REPEAT
  INPUT "Say? "; a$
  IF a$ <> "" THEN obey a$
UNTIL a$ = ""
PRINT "OpticVoice finished. RUN to start again."
END
'
DEF PROC title
  PRINT "OpticVoice 1.1 - text to speech for OpticOS (48K, beeper)"
  PRINT "(c) 2026 Optica Technology Design"
  PRINT "Uses the NRL letter-to-sound rules (Elovitz et al., 1976,"
  PRINT "public domain). Allophone numbering after the GI SP0256-AL2;"
  PRINT "all sounds newly synthesised. Runs on OpticOS."
  PRINT "Type text and press ENTER to hear it; SPACE stops speech."
  PRINT "Commands: PITCH n (24-56, 37 normal), TUNE ON, TUNE OFF,"
  PRINT "1-5 presets, HELP. ENTER on its own quits."
ENDPROC
'
DEF PROC obey(c$)
  LOCAL u$
  u$ = UPPER$(c$)
  CASE u$ OF
    WHEN "1"
      say "Hello Nathan."
    WHEN "2"
      say "Optica Technology Design."
    WHEN "3"
      say "I am a ZX Spectrum."
    WHEN "4"
      say "Hello Nathan."
      say "Optica Technology Design."
      say "I am a ZX Spectrum."
    WHEN "5"
      say "Hello Nathan, are you ready?"
    WHEN "HELP"
      title
    WHEN "TUNE ON"
      POKE 45077, 1
      PRINT "Intonation on"
    WHEN "TUNE OFF"
      POKE 45077, 0
      PRINT "Monotone"
    OTHERWISE
      IF LEFT$(u$, 6) = "PITCH " THEN setpitch VAL MID$(u$, 7, 3)
      IF LEFT$(u$, 6) <> "PITCH " THEN say c$
  ENDCASE
ENDPROC
'
DEF PROC setpitch(p)
  IF p >= 24 AND p <= 56 THEN POKE 45076, p
  PRINT "Pitch "; PEEK(45076); " (24 to 56, 37 is normal)"
ENDPROC
'
DEF PROC say(s$)
  LOCAL a, i, n
  IF LEN s$ > 250 THEN s$ = LEFT$(s$, 250)
  a = DPEEK(45071)
  FOR i = 1 TO LEN s$
    POKE a + i - 1, ASC MID$(s$, i, 1)
  NEXT
  POKE a + LEN s$, 0
  n = USR 45056
  IF PEEK(45075) THEN PRINT "(stopped)"
ENDPROC
'
DEF PROC start
  ' Saved with AUTO start: RUN begins at the top, where CLEAR
  ' can be used (not inside a PROC).
  RUN
ENDPROC
