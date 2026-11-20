' ===========================================================
' OPTICBASIC 128: SAY - prototype demo. Needs OpticOS 128:
' OpticOS in ROM slot 0 and the SAY extension ROM in slot 1
' (Fuse: --machine 128 --rom-128-0 opticos.rom
'        --rom-128-1 opticos128ext.rom).
' SAY LOAD loads the speech data from this tape into RAM banks
' 4, 6, 1, 3; then SAY works in programs and typed lines:
'   SAY "text"  SAY a$  SAY PITCH n  SAY VOICE AY|BUZZER
'   SAY TUNE 0|1
' ===========================================================
PRINT "Loading the speech data..."
SAY LOAD
CLS
PRINT INK 5; "OpticBASIC 128: SAY"
PRINT
PRINT "Speech data is in banks 4,6,1,3."
PRINT "Try typing:"
PRINT "  SAY ""HELLO NATHAN"""
PRINT "  SAY VOICE BUZZER   (or AY)"
PRINT "  SAY PITCH 30       (37 normal)"
PRINT "  SAY TUNE 0         (monotone)"
PRINT "  greet ""Nathan""     (a PROC)"
PRINT
SAY VOICE AY
SAY "Speech is ready."
END
'
DEF PROC greet(n$)
  LOCAL a$
  a$ = "Hello " + n$ + ", are you ready?"
  PRINT a$
  SAY a$
ENDPROC
'
DEF PROC start
  RUN
ENDPROC
