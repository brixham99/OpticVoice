10 REM OpticVoice 1.0 for the standard 48K ROM. (c) 2026 Optica Technology Design. MIT licence (code). CODE "ovcode48" 46080,18231: LET n=USR 46080 says the text at PEEK 46095+256*PEEK 46096 (0 ends it); USR 46083 says the allophone list at 46091/2; USR 46086 converts only. 46097/8 "SP", 46099 stopped, 46100 pitch, 46101 tune, 46102 variants, 46103 version.
20 CLEAR 46079
30 IF PEEK 46097<>83 OR PEEK 46098<>80 OR PEEK 46103<>3 THEN LOAD "ovcode48"CODE
40 GO SUB 500
50 LET s$="OpticVoice ready.": GO SUB 1000
60 POKE 23692,255: INPUT "Say? "; LINE a$
70 IF a$="" THEN GO TO 9000
80 PRINT "Say? ";a$
90 GO SUB 2000: GO TO 60
500 REM title
510 PRINT "OpticVoice 1.0 - text to speech"'"for the 48K Spectrum (beeper)"
520 PRINT CHR$ 127;" 2026 Optica Technology Design"
530 PRINT "Uses the NRL letter-to-sound"'"rules (Elovitz et al., 1976,"'"public domain). Allophone"'"numbering after the GI"'"SP0256-AL2; all sounds newly"'"synthesised. Runs on the"'"standard 48K ROM."
540 PRINT "Type text and press ENTER to"'"hear it; SPACE stops speech."
550 PRINT "Commands: PITCH n (24-56, 37"'"normal), TUNE ON, TUNE OFF,"'"1-5 presets, HELP. ENTER on"'"its own quits."
560 RETURN
1000 REM say s$
1010 IF LEN s$>250 THEN LET s$=s$( TO 250)
1020 LET a=PEEK 46095+256*PEEK 46096
1030 FOR i=1 TO LEN s$: POKE a+i-1,CODE s$(i): NEXT i
1040 POKE a+LEN s$,0
1050 LET n=USR 46080
1060 IF PEEK 46099 THEN PRINT "(stopped)"
1070 RETURN
2000 REM obey a$
2010 LET u$=a$: GO SUB 3000
2020 IF u$="1" THEN LET s$="Hello Nathan.": GO SUB 1000: RETURN
2030 IF u$="2" THEN LET s$="Optica Technology Design.": GO SUB 1000: RETURN
2040 IF u$="3" THEN LET s$="I am a ZX Spectrum.": GO SUB 1000: RETURN
2050 IF u$="4" THEN LET s$="Hello Nathan.": GO SUB 1000: LET s$="Optica Technology Design.": GO SUB 1000: LET s$="I am a ZX Spectrum.": GO SUB 1000: RETURN
2060 IF u$="5" THEN LET s$="Hello Nathan, are you ready?": GO SUB 1000: RETURN
2070 IF u$="HELP" THEN GO SUB 500: RETURN
2080 IF u$="TUNE ON" THEN POKE 46101,1: PRINT "Intonation on": RETURN
2090 IF u$="TUNE OFF" THEN POKE 46101,0: PRINT "Monotone": RETURN
2100 IF LEN u$>=6 THEN IF u$( TO 6)="PITCH " THEN GO TO 4000
2110 LET s$=a$: GO SUB 1000: RETURN
3000 REM u$ to capitals
3010 FOR i=1 TO LEN u$
3020 LET c=CODE u$(i): IF c>=97 AND c<=122 THEN LET u$(i)=CHR$ (c-32)
3030 NEXT i: RETURN
4000 REM PITCH n
4010 LET p=0: LET t$=u$(7 TO ): IF LEN t$>3 THEN LET t$=t$( TO 3)
4020 FOR i=1 TO LEN t$
4030 LET c=CODE t$(i): IF c=32 THEN GO TO 4060
4040 IF c<48 OR c>57 THEN LET i=LEN t$: GO TO 4060
4050 LET p=p*10+c-48
4060 NEXT i
4070 IF p>=24 AND p<=56 THEN POKE 46100,p
4080 PRINT "Pitch ";PEEK 46100;" (24-56, 37 normal)"
4090 RETURN
9000 PRINT "OpticVoice finished. RUN to"'"start again."
