' ===========================================================
' OPTICOS SPEECH 128 - phase 3 demo for a 128K Spectrum
' running the OpticOS ROM. Resident player "sp128code" is
' CODE 38912,10240 ($9800-$BFFF, uncontended bank 2). The
' sound data is paged in at $C000 through port $7FFD:
'   bank 4 = beeper data, banks 6, 1, 3 = AY-3-8912 data.
' Same API as the 48K version, based at 38912:
'   n = USR 38912  say the text in the text buffer
'   n = USR 38915  say the allophone list at DPEEK(38923)
'   n = USR 38918  convert only: list at DPEEK(38925)
' POKE the text at DPEEK(38927), then a 0. PEEK 38931 = 1 if
' SPACE stopped it. 38932 pitch, 38933 intonation,
' 38934 variants, 38936 device (0 beeper, 1 AY), 38937 BANKM
' (the value kept in port $7FFD), USR 38938 = 1 on a 128K.
' ===========================================================
CLEAR 38911
IF PEEK(38929) <> 83 OR PEEK(38930) <> 80 OR PEEK(38935) <> 3 THEN LOAD "sp128code" CODE
IF USR 38938 = 0 THEN PRINT "This needs a 128K Spectrum. Use speech.tzx on a 48K." : STOP
OUT 32765, 20
LOAD "bank4" CODE
OUT 32765, 22
LOAD "bank6" CODE
OUT 32765, 17
LOAD "bank1" CODE
OUT 32765, 19
LOAD "bank3" CODE
OUT 32765, 16
POKE 38937, 16
POKE 38936, 1
CLS
PRINT INK 5; "OpticOS Speech 128 - phase 3"
PRINT
PRINT "1  Hello Nathan"
PRINT "2  Optica Technology Design"
PRINT "3  I am a ZX Spectrum"
PRINT "4  all three"
PRINT "5  a question"
PRINT "D  AY chip / beeper"
PRINT "P  pitch    M  intonation on/off"
PRINT
PRINT "Type a number, or any text to say."
PRINT "SPACE stops the speech. ENTER on"
PRINT "its own ends the program."
PRINT "Voice: AY chip"
REPEAT
  INPUT "Say? "; t$
  CASE t$ OF
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
    WHEN "d", "D"
      POKE 38936, 1 - PEEK(38936)
      IF PEEK(38936) THEN PRINT "Voice: AY chip" ELSE PRINT "Voice: beeper"
    WHEN "p", "P"
      p = PEEK(38932) - 4
      IF p < 29 THEN p = 45
      POKE 38932, p
      PRINT "Pitch "; p; " (37 is normal)"
    WHEN "m", "M"
      POKE 38933, 1 - PEEK(38933)
      IF PEEK(38933) THEN PRINT "Intonation on" ELSE PRINT "Monotone"
    WHEN ""
    OTHERWISE
      say t$
  ENDCASE
UNTIL t$ = ""
END
'
DEF PROC say(s$)
  LOCAL a, i, n
  IF LEN s$ > 250 THEN s$ = LEFT$(s$, 250)
  a = DPEEK(38927)
  FOR i = 1 TO LEN s$
    POKE a + i - 1, ASC MID$(s$, i, 1)
  NEXT
  POKE a + LEN s$, 0
  PRINT s$; " ";
  n = USR 38912
  IF PEEK(38931) THEN PRINT "(stopped)" ELSE PRINT "("; n; " allophones)"
ENDPROC
'
DEF PROC start
  RUN
ENDPROC
