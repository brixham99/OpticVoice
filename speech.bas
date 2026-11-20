' ===========================================================
' OPTICOS SPEECH - phase 1 demo (OpticOS ROM v1.0.3)
' Text to speech through the beeper. The machine code block
' "speechcode" (CODE 45056,18690) does the work:
'   n = USR 45056  say the text in the text buffer
'   n = USR 45059  say the allophone list at DPEEK(45067)
'   n = USR 45062  convert only: list at DPEEK(45069)
' POKE the text at DPEEK(45071), then a 0. n is the number
' of allophones. Interrupts are off while it speaks.
' ===========================================================
CLEAR 45055
IF PEEK(45073) <> 83 OR PEEK(45074) <> 80 THEN LOAD "speechcode" CODE
CLS
PRINT INK 5; "OpticOS Speech - phase 1"
PRINT
PRINT "1  Hello Nathan"
PRINT "2  Optica Technology Design"
PRINT "3  I am a ZX Spectrum"
PRINT "4  all three"
PRINT
PRINT "Type a number, or any text to say."
PRINT "Press ENTER on its own to stop."
REPEAT
  INPUT "Say? "; t$
  CASE t$ OF
    WHEN "1"
      say "Hello Nathan"
    WHEN "2"
      say "Optica Technology Design"
    WHEN "3"
      say "I am a ZX Spectrum"
    WHEN "4"
      say "Hello Nathan."
      say "Optica Technology Design."
      say "I am a ZX Spectrum."
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
  a = DPEEK(45071)
  FOR i = 1 TO LEN s$
    POKE a + i - 1, ASC MID$(s$, i, 1)
  NEXT
  POKE a + LEN s$, 0
  PRINT s$; " ";
  n = USR 45056
  PRINT "("; n; " allophones)"
ENDPROC
'
DEF PROC start
  ' Saved with AUTO start: RUN begins at the top, where CLEAR
  ' can be used (not inside a PROC).
  RUN
ENDPROC
