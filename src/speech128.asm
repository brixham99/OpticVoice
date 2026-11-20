M128    equ 1
AYPAD   equ 115
; =====================================================================
; OpticOS Speech - phase 2: a software text-to-speech synthesiser for the
; 48K Spectrum running OpticOS. Text -> NRL letter-to-sound rules ->
; SP0256-style allophone codes -> context variants and intonation ->
; pre-synthesised 1-bit allophones played through the beeper (port $FE
; bit 4) at 31,250 bits a second (112 T each), voiced periods shortened or
; lengthened for pitch. tools/gen.py turns this file into speech.asm (the
; timing code and the tables) and assembles it.  CLEAR 45055 first.
;
;   45056  n = USR 45056   say the text at TEXTPTR (0 or 13 ends it)
;   45059  n = USR 45059   say the allophone list at LISTPTR ($FF ends it;
;                          bits 6-7 of a code = pitch level 0 mid, 1 low, 2 high, 3 top)
;   45062  n = USR 45062   convert only: text at TEXTPTR -> allophone list
;                          at ALLBUF ($FF ends it)
;   n = the number of allophones.  45065 TEXTPTR, 45067 LISTPTR (DPOKE),
;   45069 ALLBUF address, 45071 TEXTBUF address (read only), 45073 "SP",
;   45075 STOPPED (1 if SPACE stopped the speech), 45076 PITCH (period in
;   bytes, 37 = 105.6 Hz; smaller is higher, 24-56), 45077 INTON (0 = monotone),
;   45078 VARIANTS (0 = no context variants), 45079 version (2)
; =====================================================================
BORDCR  equ $5C48
FLAGS   equ $5C3B                ; bit 5: a new key is ready (OpticOS keeps this)
NBYTE   equ 37
PAD     equ $AA
QMARK   equ $44
        org 38912
        jp say_text
        jp say_list
        jp convert
TEXTPTR: dw textbuf
LISTPTR: dw allbuf
        dw allbuf
        dw textbuf
        db "SP"                 ; 45073: signature, so BASIC can tell the code is loaded
STOPPED: db 0                   ; 45075
PITCH:  db NBYTE                ; 45076
INTON:  db 1                    ; 45077
VARIANTS: db 1                  ; 45078
        db 3                    ; 45079: version
DEVICE: db 0                    ; +24: 0 beeper, 1 AY (128K build only)
BANKM:  db $10                  ; +25: port $7FFD value to restore after paging (128K build)
        jp detect               ; +26: n = 1 if 128K paging works, else 0
        dw dirb                 ; +29: beeper allophone directory (128K: bank, address x 64)
        dw dira                 ; +31: AY allophone directory (128K)

say_text:
        call convert
        push bc
        ld hl,allbuf
        call speak
        pop bc
        ret
say_list:
        ld hl,(LISTPTR)
        push hl
        ld bc,0
sl_cnt: ld a,(hl)
        inc hl
        inc a
        jp z,sl_go
        inc bc
        jp sl_cnt
sl_go:  pop hl
        push bc
        call speak
        pop bc
        ret
speak:
 IF M128
        ld a,(DEVICE)
        or a
        jp nz,play_ay
 ENDIF
        jp play

; ---------------------------------------------------------------------
; play: HL = allophone codes, $FF ends.  Interrupts are off while it plays;
; SPACE (and so BREAK) is checked before each allophone.
play:   di
        ld (qptr),hl
        xor a
        ld (STOPPED),a
        ld a,(BORDCR)
        rra
        rra
        rra
        and 7
        ld b,a                  ; B = border colour, bit 4 (speaker) clear
        out ($FE),a
q_next: ld a,$7F                ; SPACE row: bit 0 low = pressed
        in a,($FE)
        rra
        jp nc,q_stop
        ld hl,(qptr)
        ld a,(hl)
        inc hl
        ld (qptr),hl
        cp $FF
        jp z,q_end
        ld c,a
        rlca                    ; pitch level (bits 6-7) -> voiced period length
        rlca
        and 3
        ld e,a
        ld d,0
        ld hl,poffs
        add hl,de
        ld a,(PITCH)
        add a,(hl)
        cp 8
        jp nc,q_p1
        ld a,8
q_p1:   ld d,0
        cp NBYTE+1
        jp c,q_p2
        sub NBYTE
        ld d,a                  ; D = pad bytes
        ld a,NBYTE
q_p2:   ld (vdat),a             ; data bytes of a voiced period
        ld a,d
        ld (vpad),a
        ld a,c
        ld hl,dirb
        call alook
f_next: ld a,(hl)               ; frame header: 0 end, $80+n n silent frames,
        inc hl                  ; else bits 0-5 = repeats of the 37-byte period that
        or a                    ; follows, bit 6 = voiced (its length follows the pitch)
        jp z,q_next
        jp m,f_sil
        push hl
        pop ix
        ld c,a
        ld d,0
        and $40
        ld a,NBYTE
        jp z,f_unv
        ld a,(vpad)
        ld d,a
        ld a,(vdat)
f_unv:  ld (fdat),a
        ld a,d
        ld (fpad),a
        ld a,c
        and $3F
        ld c,a
f_rep:  ld a,(fdat)
        ld d,a
bloop:  ld e,(hl)
        inc hl
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd19:    dec a
        jr nz,pd19
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd21:    dec a
        jr nz,pd21
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd23:    dec a
        jr nz,pd23
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd25:    dec a
        jr nz,pd25
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd27:    dec a
        jr nz,pd27
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd29:    dec a
        jr nz,pd29
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd31:    dec a
        jr nz,pd31
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,1
pd33:    dec a
        jr nz,pd33
        ld a,0
        ld a,0
        ld a,0
        nop
        nop
        nop
        dec d
        jp nz,bloop
        ld a,(fpad)
        or a
        jp z,f_np
        ld d,a
ploop:  ld e,PAD
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd20:    dec a
        jr nz,pd20
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd22:    dec a
        jr nz,pd22
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd24:    dec a
        jr nz,pd24
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd26:    dec a
        jr nz,pd26
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd28:    dec a
        jr nz,pd28
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd30:    dec a
        jr nz,pd30
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd32:    dec a
        jr nz,pd32
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,3
pd34:    dec a
        jr nz,pd34
        ld a,0
        dec d
        jp nz,ploop
f_np:   dec c
        jp z,f_done
        push ix
        pop hl
        jp f_rep
f_done: ld de,NBYTE
        add ix,de
        push ix
        pop hl
        jp f_next
f_sil:  and $7F
        ld c,a
s_frm:  ld de,1381              ; 1381 x 24 T ~ one frame (296 x 112 T); jp nz is 10 T
s_lp:   dec de
        ld a,d
        or e
        jp nz,s_lp
        dec c
        jp nz,s_frm
        jp f_next
q_stop: ld a,1
        ld (STOPPED),a
qs_w:   ld a,$7F                ; wait for SPACE to be let go, so BASIC does not see it
        in a,($FE)
        rra
        jp nc,qs_w
        ld hl,FLAGS             ; and drop a SPACE BASIC may already have seen
        res 5,(hl)
q_end:  ld a,b
        out ($FE),a
 IF M128
        call unpage
 ENDIF
        ei
        ret

; alook: A = allophone code (bits 0-5), HL = its directory -> HL = its data.
; On the 128K build the directory holds (bank, address) and the bank is paged in at $C000.
alook:
 IF M128
        and 63
        ld e,a
        add a,a
        add a,e
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        push bc
        ld c,a
        ld a,(BANKM)
        and $F8
        or c
        ld bc,$7FFD
        out (c),a
al_pg:  pop bc                  ; (label: the rig's test emulates paging here)
        ex de,hl
        ret
unpage: push bc
        ld a,(BANKM)
        ld bc,$7FFD
        out (c),a
        pop bc
        ret
 ELSE
        and 63
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
 ENDIF

; detect: n = USR (base+26): 1 if port $7FFD pages RAM at $C000 (a 128K), else 0
detect: di
        ld bc,$7FFD
        ld a,(BANKM)
        and $F8
        out (c),a
        ld hl,$C000
        ld e,(hl)
        ld (hl),$55
        or 1
        out (c),a
        ld d,(hl)
        ld (hl),$AA
        and $F8
        out (c),a
        ld a,(hl)
        ld (hl),e
        ld bc,0
        cp $55
        jp nz,dt_x
        ld a,(BANKM)
        and $F8
        or 1
        push bc
        ld bc,$7FFD
        out (c),a
        pop bc
        ld (hl),d
        inc c
dt_x:   push bc
        ld a,(BANKM)
        ld bc,$7FFD
        out (c),a
        pop bc
        ei
        ret
poffs:  db 0,4,256-4,256-7      ; pitch levels: mid, low, high, top

 IF M128
; ---------------------------------------------------------------------
; play_ay: HL = allophone codes, $FF ends. AY-3-8912 sample playback: tone and
; noise off, each sample byte indexes aytab (3 pages: volumes A, B, C), one
; sample every 259 T (13,513 Hz); a voiced period is 128 samples (+ pitch).
play_ay: di
        ld (qptr),hl
        xor a
        ld (STOPPED),a
        call ay_on
a_next: ld a,$7F
        in a,($FE)
        rra
        jp nc,a_stop
        ld hl,(qptr)
        ld a,(hl)
        inc hl
        ld (qptr),hl
        cp $FF
        jp z,a_end
        ld c,a
        rlca
        rlca
        and 3
        ld e,a
        ld d,0
        ld hl,poffs
        add hl,de
        ld a,(PITCH)
        add a,(hl)
        sub NBYTE               ; signed offset d
        ld e,a
        add a,a
        add a,a
        add a,a
        sub e                   ; 7d
        sra a                   ; 7d >> 1
        add a,128               ; L = 128 + 7d/2 samples
        cp 16
        jp nc,a_p1
        ld a,16
a_p1:   ld d,0
        cp 129
        jp c,a_p2
        sub 128
        ld d,a
        ld a,128
a_p2:   ld (vdat),a
        ld a,d
        ld (vpad),a
        ld a,c
        ld hl,dira
        call alook
af_next: ld a,(hl)
        inc hl
        or a
        jp z,a_next
        jp m,af_sil
        push hl
        pop ix
        ld c,a
        ld d,0
        and $40
        ld a,128
        jp z,af_unv
        ld a,(vpad)
        ld d,a
        ld a,(vdat)
af_unv: ld (fdat),a
        ld a,d
        ld (fpad),a
        ld a,c
        and $3F
        ld (frep),a
af_rep: ld a,(fdat)
        ld (cnt),a
        ld c,$FD
        ld d,aytab/256
ays_lp:
        ld e,(hl)
        inc hl
        ld b,$FF
        ld a,8
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        inc d
        ld b,$FF
        ld a,9
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        inc d
        ld b,$FF
        ld a,10
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        dec d
        dec d
        ld a,2
pd35:    dec a
        jr nz,pd35
        ld a,(cnt)
        dec a
        ld (cnt),a
        jp nz,ays_lp
        ld a,(fpad)
        or a
        jp z,af_np
        ld (cnt),a
ayp_lp:
        ld e,AYPAD
        ld b,$FF
        ld a,8
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        inc d
        ld b,$FF
        ld a,9
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        inc d
        ld b,$FF
        ld a,10
        out (c),a
        ld b,$BF
        ld a,(de)
        out (c),a
        dec d
        dec d
        ld a,1
pd36:    dec a
        jr nz,pd36
        ld a,0
        ld a,0
        nop
        nop
        ld a,(cnt)
        dec a
        ld (cnt),a
        jp nz,ayp_lp
af_np:  ld a,(frep)
        dec a
        ld (frep),a
        jp z,af_done
        push ix
        pop hl
        jp af_rep
af_done: ld de,128
        add ix,de
        push ix
        pop hl
        jp af_next
af_sil: and $7F
        ld c,a
as_frm: ld de,1381              ; one period of silence, as the beeper player
as_lp:  dec de
        ld a,d
        or e
        jp nz,as_lp
        dec c
        jp nz,as_frm
        jp af_next
a_stop: ld a,1
        ld (STOPPED),a
as_w:   ld a,$7F
        in a,($FE)
        rra
        jp nc,as_w
        ld hl,FLAGS
        res 5,(hl)
a_end:  call ay_off
        call unpage
        ei
        ret
; ay_on: mixer all off (each channel = its volume), fade up to the zero level
ay_on:  ld bc,$FFFD
        ld a,7
        out (c),a
        ld b,$BF
        ld a,$3F
        out (c),a
        ld e,0
ao_lp:  call aywr
        ld a,e
        cp AYPAD
        ret z
        inc e
        jp ao_lp
ay_off: ld e,AYPAD
af_lp:  call aywr
        ld a,e
        or a
        ret z
        dec e
        jp af_lp
; aywr: write the volumes of table entry E, then wait ~30 us
aywr:   ld d,aytab/256
        ld c,$FD
        ld a,8
aw_lp:  ld b,$FF
        out (c),a
        ld b,$BF
        ex af,af'
        ld a,(de)
        out (c),a
        ex af,af'
        inc d
        inc a
        cp 11
        jp nz,aw_lp
        ld a,6
aw_d:   dec a
        jp nz,aw_d
        ret
 ENDIF

; ---------------------------------------------------------------------
; convert: text at (TEXTPTR) -> allophone codes at allbuf, $FF ended.
; BC = number of codes.  Same rules and matcher as tools/front.py.
convert:
        xor a
        ld (wbuf-1),a           ; zeros before the text: never letters
        ld (wbuf-2),a
        ld hl,(TEXTPTR)
        ld de,wbuf
        ld a,' '
        ld (de),a               ; wbuf[0]: the position before the text
        inc de
        ld (de),a               ; the leading space
        inc de
        ld b,250
cv_nl:  ld a,(hl)
        inc hl
        or a
        jp z,cv_ne
        cp 13
        jp z,cv_ne
        call mapch
        cp ' '
        jp nz,cv_put
        dec de
        ld a,(de)
        inc de
        cp ' '
        jp z,cv_skip            ; runs of spaces become one
        ld a,' '
cv_put: ld (de),a
        inc de
cv_skip: djnz cv_nl
cv_ne:  dec de
        ld a,(de)
        inc de
        cp ' '
        jp z,cv_e2
        ld a,' '
        ld (de),a
        inc de
cv_e2:  xor a
        ld (de),a
        ld hl,allbuf
        ld (outp),hl
        ld hl,wbuf+1
; --- for each character
c_loop: ld (cur),hl
        ld a,(hl)
        or a
        jp z,c_done
        sub 32
        jp c,c_skip
        cp 64
        jp nc,c_skip
        add a,a
        ld e,a
        ld d,0
        ld ix,gindex
        add ix,de
        ld e,(ix+0)
        ld d,(ix+1)
        ld a,d
        or e
        jp z,c_skip
        push de
        pop ix                  ; IX = first rule of the group
r_try:  ld a,(ix+0)
        cp $FF
        jp z,c_skip             ; no rule: skip the character
        ld (lptr),ix
        call nextpart
        ld (mptr),ix
        call nextpart
        ld (rptr),ix
        call nextpart
        ld (optr),ix
        call nextpart           ; IX = the next rule
        ; the rest of the match string
        ld hl,(cur)
        inc hl
        ld de,(mptr)
        ld a,(de)
        cp $80
        jp z,r_mok
r_m:    ld a,(de)
        and $7F
        cp (hl)
        jp nz,r_try
        inc hl
        ld a,(de)
        inc de
        rla
        jp nc,r_m
r_mok:  ld (rpos),hl            ; just past the match
        ; left context, leftwards from cur-1
        ld hl,(cur)
        dec hl
        ld de,(lptr)
        call ctx_left
        jp nz,r_try
        ; right context
        ld hl,(rpos)
        ld de,(rptr)
        call ctx_right
        jp nz,r_try
        ; matched: emit
        ld hl,(optr)
        ld a,(hl)
        cp $80
        jp z,r_emitd
r_e:    ld a,(hl)
        and $7F
        call emit
        ld a,(hl)
        inc hl
        rla
        jp nc,r_e
r_emitd: ld hl,(rpos)
        jp c_loop
c_skip: ld hl,(cur)
        inc hl
        jp c_loop
c_done: ld hl,(outp)
        ld (hl),$FF
        call post
        ld hl,(outp)
        ld de,allbuf
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ret

; emit A: pauses (0-4, and QMARK = PA5 + flag) at the start are dropped, a pause
; after a pause keeps the larger
emit:   push hl
        ld hl,(outp)
        ld c,a
        and 63
        cp 5
        ld a,c
        jp nc,em_put
        ld de,allbuf
        push hl
        or a
        sbc hl,de
        pop hl
        jp z,em_x               ; nothing yet: drop a leading pause
        dec hl
        ld a,(hl)
        and 63
        cp 5
        jp nc,em_p2
        ld a,(hl)
        cp c                    ; previous is a pause: keep the larger
        jp nc,em_x
        ld (hl),c
        jp em_x
em_p2:  inc hl
        ld a,c
em_put: ld de,allbuf+510
        ex de,hl
        or a
        sbc hl,de
        ex de,hl
        jp c,em_x               ; full
        ld (hl),a
        inc hl
        ld (outp),hl
em_x:   pop hl
        ret

; post: context variants (ctab/vtab, as tools/front.py postprocess), then
; intonation: the last word before '.' or the end gets level 1 (low), before
; '?' level 2 (high); QMARK becomes PA5
post:   ld ix,allbuf
        ld a,(VARIANTS)
        or a
        jp z,pp_int
        ld d,0                  ; D = 5 if the previous allophone is a consonant
pv_lp:  ld a,(ix+0)
        cp $FF
        jp z,pp_int
        ld b,a
        and $C0
        jp nz,pv_prev
        ld a,b
        call ctabof
        and $78
        jp z,pv_prev            ; not in a family
        rrca
        rrca
        rrca
        dec a
        ld c,a
        add a,a
        add a,a
        add a,c
        add a,a                 ; (family-1) * 10
        add a,d
        ld c,a
        ld e,0                  ; next class: pause at the end
        ld a,(ix+1)
        cp $FF
        jp z,pv_n
        call ctabof
        and 7
        ld e,a
pv_n:   ld a,c
        add a,e
        ld l,a
        ld h,0
        push de
        ld de,vtab
        add hl,de
        pop de
        ld a,(hl)
        ld (ix+0),a
pv_prev: ld a,(ix+0)
        call ctabof
        and 7
        cp 1
        ld d,0
        jp nz,pv_nx
        ld d,5
pv_nx:  inc ix
        jp pv_lp
pp_int: ld ix,allbuf
        ld hl,allbuf            ; HL = the first allophone of the current word
pi_lp:  ld a,(ix+0)
        cp $FF
        jp z,pi_end
        ld c,a
        and 63
        cp 5
        jp nc,pi_nx             ; not a pause
        ld a,c
        ld b,2                  ; kind: 2 before '?', 1 before '.' (PA5), 0 inside
        cp QMARK
        jp z,pi_mk
        ld b,1
        cp 4
        jp z,pi_mk
        ld b,0
pi_mk:  push bc
        call word
        pop bc
        ld a,c
        and 63
        ld (ix+0),a
        push ix
        pop hl
        inc hl
pi_nx:  inc ix
        jp pi_lp
pi_end: ld b,1
; word: codes HL .. IX-1 are one word, B its kind. Pitch levels (bits 6-7): the stressed
; vowel (flagged by an exception, else the first) of a word of 2+ vowels gets the
; accent level, the rest the base (lvtab); flags cleared. INTON 0: all level 0.
word:   ld (wend),ix
        ld (wst),hl
        ld c,0
        ld e,0
        ld a,(INTON)
        or a
        jp z,wd_lv
        ld a,b
        add a,a
        ld e,a
        ld d,0
        ld hl,lvtab
        add hl,de
        ld c,(hl)
        inc hl
        ld e,(hl)
wd_lv:  ld a,c
        ld (wbase),a
        ld a,e
        ld (wacc),a
        ld hl,0
        ld (wpos),hl
        xor a
        ld (wcnt),a
        ld (wfl),a
        ld hl,(wst)
        ld de,(wend)
w1_lp:  push hl
        or a
        sbc hl,de
        pop hl
        jp z,w1_done
        ld a,(hl)
        bit 6,a
        jp z,w1_nf
        ld a,(wfl)
        or a
        jp nz,w1_nf
        inc a
        ld (wfl),a
        ld (wpos),hl
w1_nf:  ld a,(hl)
        push hl
        call ctabof
        pop hl
        and $80
        jp z,w1_nx
        ld a,(wcnt)
        inc a
        ld (wcnt),a
        dec a
        jp nz,w1_nx             ; not the first vowel
        ld a,(wfl)
        or a
        jp nz,w1_nx
        ld (wpos),hl
w1_nx:  inc hl
        jp w1_lp
w1_done: ld hl,(wst)
w2_lp:  push hl
        or a
        sbc hl,de
        pop hl
        ret z
        ld a,(wbase)
        ld c,a
        ld a,(wcnt)
        cp 2
        jp c,w2_set
        push hl
        push de
        ld de,(wpos)
        or a
        sbc hl,de
        pop de
        pop hl
        jp nz,w2_set
        ld a,(wacc)
        ld c,a
w2_set: ld a,(hl)
        and 63
        or c
        ld (hl),a
        inc hl
        jp w2_lp
lvtab:  db $00,$80, $40,$00, $80,$C0
ctabof: and 63                  ; A = ctab[A & 63]
        push de
        ld e,a
        ld d,0
        ld hl,ctab
        add hl,de
        pop de
        ld a,(hl)
        ret

; mapch: A -> A-Z, 0-9, , . ? - ' or a space (as tools/front.py normalise)
mapch:  cp 'a'
        jp c,mc_1
        cp 'z'+1
        jp nc,mc_sp
        sub 32
        ret
mc_1:   cp 'A'
        jp c,mc_2
        cp 'Z'+1
        ret c
        jp mc_sp
mc_2:   cp '0'
        jp c,mc_3
        cp '9'+1
        ret c
mc_3:   cp '!'
        jp nz,mc_4
        ld a,'.'
        ret
mc_4:   cp ';'
        jp z,mc_c
        cp ':'
        jp nz,mc_5
mc_c:   ld a,','
        ret
mc_5:   cp ','
        ret z
        cp '.'
        ret z
        cp '?'
        ret z
        cp '-'
        ret z
        cp "'"
        ret z
mc_sp:  ld a,' '
        ret

; IX past one rule part (the byte with bit 7 set ends it)
nextpart:
        ld a,(ix+0)
        inc ix
        rla
        jp nc,nextpart
        ret

; letter flags of A: 1 vowel 2 consonant 4 voiced 8 front 16 sibilant 32 "@"; Z if not a letter
flagsof: sub 'A'
        jp c,fo_no
        cp 26
        jp nc,fo_no
        push hl
        ld hl,lflags
        add a,l
        ld l,a
        jp nc,fo_1
        inc h
fo_1:   ld a,(hl)
        pop hl
        or a
        ret
fo_no:  xor a
        ret

; ctx_left: DE = pattern (reversed), HL = text going left. Z = match
ctx_left:
        ld a,(de)
        cp $80
        ret z
cl_el:  ld a,(de)
        and $7F
        ld c,a
        call left1
        ret nz
        ld a,(de)
        inc de
        rla
        jp nc,cl_el
        xor a
        ret
left1:  ld a,c
        cp 10
        jp c,l_cls
        cp (hl)                 ; a literal
        ret nz
        dec hl
        ret
l_cls:  cp 9
        jp z,l_space
        cp 1
        jp z,l_vow
        cp 2
        jp z,l_colon
        cp 3
        ld c,2
        jp z,l_one
        cp 4
        ld c,4
        jp z,l_one
        cp 5
        ld c,8
        jp z,l_one
        cp 7
        jp z,l_amp
        cp 8
        jp z,l_at
        or a                    ; % (not used on the left): fail
        ret
l_space: ld a,(hl)
        call flagsof
        jp nz,l_fail
        dec hl
        xor a
        ret
l_vow:  ld a,(hl)
        call flagsof
        and 1
        jp z,l_fail
lv_1:   dec hl
        ld a,(hl)
        call flagsof
        and 1
        jp nz,lv_1
        xor a
        ret
l_colon: ld a,(hl)
        call flagsof
        and 2
        jp z,l_ok
        dec hl
        jp l_colon
l_one:  ld a,(hl)
        call flagsof
        and c
        jp z,l_fail
        dec hl
l_ok:   xor a
        ret
l_fail: or 1
        ret
l_amp:  ld c,16
        ld b,'C'
        ld a,'S'
        jp l_two
l_at:   ld c,32
        ld b,'T'
        ld a,'C'
l_two:  ld (two_a),a
        ld a,(hl)
        call flagsof
        and c
        jp nz,l_one1
        ld a,(hl)
        cp 'H'
        jp nz,l_fail
        dec hl
        ld a,(hl)
        cp b
        jp z,l_two2
        cp 'S'
        jp z,l_two2
        push hl
        ld hl,two_a
        cp (hl)
        pop hl
        jp nz,l_fail2
l_two2: dec hl
        xor a
        ret
l_fail2: inc hl
        jp l_fail
l_one1: dec hl
        xor a
        ret

; ctx_right: DE = pattern, HL = text going right (a 0 ends the text and is never passed). Z = match
ctx_right:
        ld a,(de)
        cp $80
        ret z
cr_el:  ld a,(de)
        and $7F
        ld c,a
        call right1
        ret nz
        ld a,(de)
        inc de
        rla
        jp nc,cr_el
        xor a
        ret
rinc:   ld a,(hl)               ; step right, but never past the end
        or a
        ret z
        inc hl
        ret
right1: ld a,c
        cp 10
        jp c,r_cls
        cp (hl)
        ret nz
        inc hl
        xor a
        ret
r_cls:  cp 9
        jp z,r_space
        cp 1
        jp z,r_vow
        cp 2
        jp z,r_colon
        cp 3
        ld c,2
        jp z,r_one
        cp 4
        ld c,4
        jp z,r_one
        cp 5
        ld c,8
        jp z,r_one
        cp 6
        jp z,r_pct
        cp 7
        ld c,16
        jp z,r_two
        ld c,32                 ; 8: @
        jp r_two
r_space: ld a,(hl)
        call flagsof
        jp nz,r_fail
        call rinc
        xor a
        ret
r_vow:  ld a,(hl)
        call flagsof
        and 1
        jp z,r_fail
rv_1:   inc hl
        ld a,(hl)
        call flagsof
        and 1
        jp nz,rv_1
        xor a
        ret
r_colon: ld a,(hl)
        call flagsof
        and 2
        jp z,r_ok
        inc hl
        jp r_colon
r_one:  ld a,(hl)
        call flagsof
        and c
        jp z,r_fail
        inc hl
r_ok:   xor a
        ret
r_fail: or 1
        ret
r_two:  inc hl                  ; CH or SH (and TH for @) count as one
        ld a,(hl)
        dec hl
        cp 'H'
        jp nz,r_two1
        ld a,(hl)
        cp 'C'
        jp z,r_two2
        cp 'S'
        jp z,r_two2
        cp 'T'
        jp nz,r_two1
        ld a,c
        cp 32
        jp nz,r_two1
r_two2: inc hl
        inc hl
        xor a
        ret
r_two1: ld a,(hl)
        call flagsof
        and c
        jp z,r_fail
        inc hl
        xor a
        ret
r_pct:  push de                 ; % : ING, ELY, ER, ES, ED or E
        ld de,sfx
rp_1:   ld a,(de)
        or a
        jp z,rp_no
        push hl
rp_2:   ld a,(de)
        and $7F
        cp (hl)
        jp nz,rp_nx
        inc hl
        ld a,(de)
        inc de
        rla
        jp nc,rp_2
        pop af                  ; drop the saved text pointer
        pop de
        xor a
        ret
rp_nx:  pop hl
rp_3:   ld a,(de)
        inc de
        rla
        jp nc,rp_3
        jp rp_1
rp_no:  pop de
        jp r_fail
sfx:    db "IN",'G'+128,"EL",'Y'+128,"E",'R'+128,"E",'S'+128,"E",'D'+128,'E'+128,0

qptr:   dw 0
cur:    dw 0
outp:   dw 0
lptr:   dw 0
mptr:   dw 0
rptr:   dw 0
optr:   dw 0
rpos:   dw 0
two_a:  db 0
vdat:   db 0
wend:   dw 0
wst:    dw 0
wpos:   dw 0
wcnt:   db 0
wfl:    db 0
wbase:  db 0
wacc:   db 0
cnt:    db 0
frep:   db 0
curdir: dw 0
vpad:   db 0
fdat:   db 0
fpad:   db 0
; ---- tables generated by tools/gen.py
gindex:
        dw rules+0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw rules+14
        dw 0
        dw 0
        dw 0
        dw 0
        dw rules+40
        dw rules+45
        dw rules+50
        dw 0
        dw rules+55
        dw rules+64
        dw rules+72
        dw rules+79
        dw rules+87
        dw rules+95
        dw rules+103
        dw rules+112
        dw rules+122
        dw rules+129
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
        dw rules+137
        dw 0
        dw rules+142
        dw rules+392
        dw rules+526
        dw rules+633
        dw rules+723
        dw rules+954
        dw rules+994
        dw rules+1086
        dw rules+1185
        dw rules+1357
        dw rules+1362
        dw rules+1384
        dw rules+1487
        dw rules+1566
        dw rules+1629
        dw rules+1992
        dw rules+2067
        dw rules+2086
        dw rules+2142
        dw rules+2368
        dw rules+2644
        dw rules+2722
        dw rules+2744
        dw rules+2932
        dw rules+2938
        dw rules+3019
        dw 0
        dw 0
        dw 0
        dw 0
        dw 0
lflags:
        db 1,6,18,38,9,2,22,2,9,54,2,38,6,38,1,2
        db 2,38,50,34,1,6,6,18,9,54
ctab:
        db 0,0,0,0,0,131,131,130,9,1,1,57,130,25,76,131
        db 1,25,65,130,130,33,131,131,131,2,130,49,41,1,131,131
        db 131,33,17,1,17,1,1,76,1,9,9,1,1,84,3,130
        db 3,2,1,131,131,131,65,1,57,49,131,131,130,17,211,41
vtab:
        db 41,41,42,8,8,41,41,42,8,8,61,61,36,34,34,61
        db 61,36,34,34,17,17,13,13,13,17,17,13,13,13,21,21
        db 33,33,33,21,21,33,33,33,28,28,63,63,63,28,28,63
        db 63,63,57,57,27,57,57,57,57,27,57,57,56,56,11,11
        db 11,56,56,11,11,11,54,54,18,18,18,54,54,18,18,18
        db 14,14,14,14,14,39,39,39,39,39,45,45,45,45,45,62
        db 62,45,45,45
rules:
        db 128,128,167,128,128,45,160,128,128,128,128,128,129,255,9,132
        db 32,211,128,171,9,69,4,2,129,32,211,128,171,9,129,32
        db 211,128,171,128,160,128,128,255,128,128,128,131,255,128,128,128
        db 131,255,128,128,128,132,255,128,128,128,43,12,14,53,129,255
        db 128,128,128,46,15,11,129,255,128,128,128,17,31,129,255,128
        db 128,128,29,14,19,129,255,128,128,128,40,53,14,129,255,128
        db 128,128,40,6,35,129,255,128,128,128,55,12,42,55,129,255
        db 128,128,128,55,7,35,15,11,129,255,128,128,128,20,17,129
        db 255,128,128,128,11,6,11,129,255,128,128,128,196,255,137,128
        db 137,143,137,78,217,137,7,11,147,137,82,197,137,24,142,137
        db 66,79,85,212,137,15,28,96,145,137,71,65,73,206,137,15
        db 36,71,139,137,76,82,69,65,68,217,137,23,45,14,71,21
        db 147,128,128,137,143,137,82,197,137,24,142,137,210,207,15,142
        db 128,210,129,7,142,3,137,211,129,20,183,128,128,87,193,143
        db 128,215,128,151,2,137,78,217,128,7,11,147,128,128,3,5
        db 129,148,2,129,76,76,217,128,15,45,147,137,204,129,15,173
        db 128,71,65,73,206,128,15,36,7,139,2,129,199,197,12,138
        db 128,128,3,5,2,129,154,2,137,128,3,5,137,148,128,128
        db 3,134,148,137,82,210,128,15,142,128,82,210,128,26,142,2
        db 137,210,137,24,142,128,210,137,179,128,210,128,24,142,128,73
        db 210,128,7,142,128,201,128,148,128,217,128,148,128,213,128,151
        db 2,129,204,137,15,173,2,129,76,211,137,15,45,171,128,76
        db 203,128,23,170,128,204,131,23,173,2,137,66,76,197,128,20
        db 28,15,173,128,66,76,197,128,15,28,15,173,128,78,199,133
        db 20,11,138,128,128,128,154,255,137,85,217,137,28,134,137,85
        db 83,217,137,28,12,43,147,137,79,79,203,137,28,30,170,137
        db 69,69,206,137,28,12,139,137,69,71,73,206,137,28,12,36
        db 76,139,137,65,83,73,195,137,28,20,55,12,170,137,69,69
        db 80,69,210,137,28,19,9,179,137,69,67,65,85,83,197,137
        db 28,12,42,87,171,137,82,79,84,72,69,210,137,28,14,15
        db 18,179,137,197,3,129,28,140,128,69,73,78,199,128,28,19
        db 12,172,137,79,84,200,137,28,53,157,137,85,211,129,28,12
        db 171,128,85,73,204,128,28,12,173,128,128,128,156,255,137,79
        db 77,197,137,42,15,144,137,79,76,79,210,137,42,15,45,179
        db 137,79,85,76,196,137,42,30,149,137,79,76,79,85,210,137
        db 42,15,45,179,137,79,77,80,85,84,69,210,137,42,15,16
        db 9,49,95,17,179,137,200,131,170,69,131,200,128,170,128,200
        db 128,178,83,137,201,129,55,134,128,201,193,165,128,201,207,165
        db 128,201,69,206,165,128,128,133,183,128,203,128,170,128,79,205
        db 134,42,15,144,128,128,128,170,255,137,207,137,21,159,137,79
        db 78,197,137,21,15,139,137,69,83,73,71,206,137,21,12,43
        db 70,139,2,129,69,196,137,21,12,149,69,132,128,137,149,69
        db 2,3,129,128,137,145,137,197,3,129,21,140,137,207,137,21
        db 159,137,79,69,211,128,21,15,171,137,79,73,78,199,128,21
        db 31,12,172,137,79,215,128,21,160,128,213,193,10,159,128,128
        db 128,149,255,137,89,197,137,134,137,65,82,76,217,137,51,45
        db 147,137,73,71,72,212,137,20,145,137,78,79,85,71,200,137
        db 12,11,79,168,2,129,128,137,128,2,3,9,167,128,137,128
        db 2,137,128,137,147,129,196,137,149,2,129,128,68,137,128,128
        db 214,69,210,7,163,128,128,3,134,147,128,82,201,129,19,14
        db 147,128,82,201,128,7,14,140,2,129,210,129,179,128,210,129
        db 7,142,128,210,128,179,137,86,69,206,128,19,35,7,139,2
        db 129,128,215,128,136,215,128,159,128,215,128,49,159,128,128,207
        db 147,7,2,129,211,137,12,171,2,129,128,83,137,128,2,129
        db 76,217,137,45,147,2,129,77,69,78,212,128,16,7,11,145
        db 128,70,85,204,128,40,30,173,128,197,128,147,128,65,82,206
        db 128,51,139,137,65,210,131,179,128,65,196,128,7,149,2,129
        db 193,137,19,143,128,193,83,213,135,128,193,128,147,128,73,71
        db 200,128,148,128,201,128,147,137,89,197,128,134,128,217,128,147
        db 128,213,128,49,159,128,128,128,135,255,137,79,85,210,137,40
        db 23,142,137,85,76,204,137,40,30,173,137,82,73,69,78,196
        db 137,40,14,7,11,149,128,85,204,128,40,30,173,128,128,128
        db 168,255,137,73,82,204,137,36,51,173,137,79,78,197,137,36
        db 23,139,137,79,79,196,137,36,30,149,137,73,86,197,137,36
        db 12,163,128,73,214,128,36,12,163,137,128,73,131,164,128,197
        db 212,36,135,85,211,71,69,211,128,36,10,7,183,128,199,128
        db 164,1,66,137,128,128,164,128,128,133,138,128,82,69,65,212
        db 128,36,14,20,145,129,200,128,128,128,128,128,164,255,137,69
        db 76,208,137,27,7,45,137,137,69,65,196,137,27,7,149,137
        db 79,85,210,137,32,179,137,65,86,197,137,27,26,163,137,79
        db 84,69,204,137,27,53,17,71,173,137,69,65,82,196,137,27
        db 51,149,137,69,76,76,207,137,27,7,45,245,137,65,214,128
        db 27,26,163,137,69,82,197,128,27,19,142,137,79,85,210,128
        db 32,179,128,79,215,128,27,160,128,128,129,155,128,128,128,128
        db 255,137,211,137,12,171,137,83,76,65,78,196,137,6,45,15
        db 11,149,137,206,128,12,139,137,128,137,134,128,206,196,6,139
        db 128,69,210,128,19,179,82,2,129,69,196,137,19,149,128,69
        db 196,137,6,149,128,69,206,128,19,7,139,128,197,212,6,135
        db 2,137,128,134,134,128,128,134,147,128,197,128,147,128,128,3
        db 5,2,129,140,128,210,129,6,142,128,218,134,6,171,128,211
        db 134,6,171,128,128,68,134,134,3,133,128,3,133,140,128,128
        db 84,134,134,2,3,129,128,3,133,140,128,128,3,133,134,128
        db 210,128,179,128,71,200,128,134,128,76,196,128,6,45,149,128
        db 71,206,137,6,139,128,71,206,131,6,139,128,71,206,134,6
        db 139,128,81,85,197,128,19,170,128,128,128,140,255,128,128,128
        db 138,255,137,69,217,137,42,147,137,78,79,215,137,11,181,137
        db 128,206,128,128,128,128,170,255,137,79,83,197,137,45,31,171
        db 137,79,86,197,137,45,15,163,137,79,65,196,137,45,53,149
        db 137,79,79,203,137,45,30,170,137,73,86,197,137,45,12,163
        db 137,69,65,82,206,137,45,51,139,137,73,84,84,76,197,137
        db 45,12,17,15,173,137,73,83,84,69,206,137,45,12,55,15
        db 139,128,207,67,129,45,181,204,128,128,128,2,3,129,128,134
        db 15,173,128,69,65,196,128,45,19,149,128,128,128,173,255,137
        db 79,86,197,137,16,31,163,137,65,78,217,137,16,7,11,147
        db 137,79,84,72,69,210,137,16,15,18,179,137,69,77,79,82
        db 217,137,16,7,16,51,147,137,65,67,72,73,78,197,137,16
        db 15,37,83,139,137,79,82,78,73,78,199,137,16,23,14,11
        db 12,172,128,79,214,128,16,31,163,128,128,128,144,255,137,79
        db 78,197,137,11,15,139,137,65,84,72,65,206,137,11,20,29
        db 15,139,197,199,133,11,138,128,199,210,44,164,128,199,129,44
        db 164,128,71,204,134,44,36,15,173,128,199,128,172,128,203,128
        db 44,170,137,79,215,137,11,160,128,128,128,139,255,137,203,137
        db 53,42,212,137,198,137,15,163,137,85,210,137,32,179,137,78
        db 197,137,46,15,139,137,78,67,197,137,46,15,11,183,137,70
        db 84,69,206,137,23,40,15,139,137,84,72,69,210,137,15,18
        db 179,137,80,84,73,67,193,137,24,9,17,12,42,143,137,80
        db 84,73,67,79,211,137,24,9,17,12,42,23,183,128,198,137
        db 15,163,128,82,79,85,71,200,128,51,181,2,129,210,137,179
        db 2,129,82,211,137,51,171,128,210,128,23,142,137,78,197,128
        db 46,15,139,128,215,128,181,137,86,69,210,128,53,35,179,128
        db 214,128,15,163,128,128,3,134,181,128,128,3,69,206,181,128
        db 128,3,73,129,181,128,204,196,53,173,128,85,71,72,212,128
        db 23,145,128,85,71,200,128,15,168,137,213,128,160,200,213,83
        db 129,160,128,85,211,128,15,183,128,85,210,128,23,142,128,85
        db 76,196,128,30,149,131,213,3,204,143,128,85,208,128,31,137
        db 128,213,128,160,128,217,128,133,128,73,78,199,128,53,12,172
        db 128,201,128,133,128,79,210,128,23,142,128,79,203,128,30,170
        db 128,79,196,128,30,149,128,207,128,159,128,128,197,181,128,128
        db 137,181,128,193,128,181,137,78,76,217,128,53,11,45,147,137
        db 78,67,197,128,46,15,11,183,128,78,32,39,32,212,128,53
        db 11,145,195,128,206,152,128,128,78,199,151,2,3,137,128,206
        db 143,201,206,128,15,139,2,129,206,137,15,139,3,129,206,128
        db 15,139,128,128,83,84,137,181,128,198,131,23,168,128,84,72
        db 69,210,128,15,18,179,128,83,211,137,23,183,2,3,129,205
        db 128,15,144,128,128,128,152,255,137,85,212,137,9,30,145,137
        db 76,65,89,69,210,137,9,45,20,179,137,69,79,80,76,197
        db 137,9,19,9,15,173,137,82,79,71,82,65,205,137,9,14
        db 53,36,14,26,144,128,200,128,168,128,69,79,208,128,9,19
        db 137,128,79,215,128,9,160,128,85,212,137,9,30,145,128,128
        db 128,137,255,128,85,65,210,128,42,46,23,142,128,213,128,42
        db 174,128,128,128,170,255,137,79,76,204,137,14,53,173,137,69
        db 65,204,137,14,19,173,137,79,65,196,137,14,53,149,137,69
        db 65,68,217,137,14,7,21,147,137,69,65,76,76,217,137,14
        db 19,45,147,137,197,3,129,14,147,128,128,128,142,255,137,79
        db 77,197,137,55,15,144,137,65,89,211,137,55,7,171,137,65
        db 73,196,137,55,7,149,137,69,86,69,206,137,55,7,35,15
        db 139,137,72,79,85,76,196,137,37,30,149,137,80,69,69,67
        db 200,137,55,9,19,178,137,73,78,67,76,65,73,210,137,55
        db 12,11,42,45,7,142,137,80,69,67,84,82,85,205,137,55
        db 9,7,42,17,14,15,144,128,200,128,165,129,73,79,206,128
        db 38,15,139,128,79,77,197,128,55,15,144,129,85,210,129,38
        db 179,128,85,210,129,37,179,129,213,129,38,159,129,83,213,129
        db 37,159,129,69,196,137,43,149,129,128,129,171,128,65,73,196
        db 128,55,7,149,131,73,79,206,128,37,15,139,128,128,211,128
        db 132,128,137,171,69,4,2,129,128,137,171,1,1,2,3,129
        db 128,137,171,1,2,3,129,128,137,183,213,128,137,183,1,2
        db 137,128,137,171,137,67,200,128,55,170,128,128,67,133,128,129
        db 205,128,43,144,129,206,9,167,43,15,139,128,128,128,183,255
        db 137,207,137,17,159,137,87,207,137,17,159,137,72,197,137,18
        db 143,137,72,69,217,137,18,148,137,79,68,65,217,137,17,15
        db 21,212,137,72,69,73,210,137,18,7,142,137,72,69,82,197
        db 137,18,7,142,137,72,79,85,71,200,137,18,181,137,72,82
        db 79,85,71,200,137,29,14,159,137,69,67,72,78,79,76,79
        db 71,217,137,17,7,42,11,88,45,15,10,147,137,72,197,137
        db 18,143,128,207,137,17,159,128,72,65,212,137,18,26,145,137
        db 72,73,211,137,18,12,183,137,72,69,217,128,18,148,137,72
        db 69,82,197,128,18,7,142,128,72,69,210,128,18,179,128,72
        db 69,73,210,128,18,7,142,137,72,65,206,137,18,26,139,137
        db 72,69,205,137,18,7,144,128,72,69,83,197,137,18,19,171
        db 137,72,69,206,128,18,7,139,128,72,82,79,85,71,200,128
        db 29,14,159,128,72,79,83,197,128,18,53,171,128,72,79,85
        db 71,200,137,18,181,137,72,85,211,128,18,15,183,128,200,128
        db 157,2,129,69,196,137,17,12,149,211,201,1,206,178,128,201
        db 207,165,128,201,193,165,128,73,69,206,128,37,15,139,128,85
        db 210,129,50,179,128,213,193,50,159,137,87,207,128,17,159,128
        db 128,128,145,255,137,206,201,49,31,139,137,206,128,15,139,137
        db 80,79,206,128,15,9,23,139,136,210,129,30,142,128,210,129
        db 49,30,142,128,210,128,179,128,128,3,137,143,128,128,3,131
        db 143,128,217,128,134,71,137,128,129,128,199,128,134,128,199,128
        db 129,174,78,129,128,128,49,159,136,128,128,159,128,128,128,49
        db 159,255,137,69,82,217,137,35,7,14,147,128,73,69,215,128
        db 35,49,159,128,128,128,163,255,137,72,207,137,27,159,137,65
        db 211,137,46,24,171,137,79,82,196,137,46,51,149,137,79,82
        db 203,137,46,51,170,137,69,82,197,137,46,179,137,72,65,212
        db 137,46,24,145,137,79,82,82,217,137,46,51,14,147,137,79
        db 77,69,206,137,46,12,16,12,139,137,79,77,65,206,137,46
        db 30,16,15,139,137,65,84,69,210,137,46,23,17,179,137,79
        db 85,76,196,137,46,30,149,137,72,69,82,197,137,46,7,142
        db 137,79,82,76,196,137,46,51,45,149,137,69,82,197,128,46
        db 179,128,193,211,46,152,128,193,212,46,152,128,72,69,82,197
        db 128,48,7,142,128,72,65,212,128,48,24,145,128,72,79,204
        db 128,27,53,173,128,72,207,128,27,159,128,200,128,176,128,65
        db 210,128,46,23,142,128,79,210,131,46,179,128,210,128,142,128
        db 128,128,174,255,128,128,128,42,183,255,137,79,213,137,49,159
        db 137,79,85,210,137,49,23,142,128,79,85,78,199,128,49,15
        db 172,137,79,213,128,49,159,137,69,211,128,49,7,183,137,128
        db 128,177,2,3,129,128,137,147,2,3,129,128,201,147,2,137
        db 128,137,134,2,137,128,129,134,2,137,128,3,5,2,129,140
        db 2,137,128,3,129,134,128,128,128,140,255,137,216,137,43,7
        db 21,71,42,183,137,69,196,137,43,7,149,137,69,82,207,137
        db 43,19,14,181,128,128,128,171,255
dirb:
        db 4
        dw 49288
        db 4
        dw 49290
        db 4
        dw 49292
        db 4
        dw 49294
        db 4
        dw 49296
        db 4
        dw 49298
        db 4
        dw 49793
        db 4
        dw 50212
        db 4
        dw 50365
        db 4
        dw 50595
        db 4
        dw 50787
        db 4
        dw 50941
        db 4
        dw 51094
        db 4
        dw 51247
        db 4
        dw 51477
        db 4
        dw 51630
        db 4
        dw 51745
        db 4
        dw 51936
        db 4
        dw 52014
        db 4
        dw 52129
        db 4
        dw 52358
        db 4
        dw 52739
        db 4
        dw 52854
        db 4
        dw 53007
        db 4
        dw 53198
        db 4
        dw 53427
        db 4
        dw 53618
        db 4
        dw 53809
        db 4
        dw 53924
        db 4
        dw 54039
        db 4
        dw 54230
        db 4
        dw 54383
        db 4
        dw 54612
        db 4
        dw 55069
        db 4
        dw 55260
        db 4
        dw 55451
        db 4
        dw 55604
        db 4
        dw 55795
        db 4
        dw 56062
        db 4
        dw 56253
        db 4
        dw 56368
        db 4
        dw 56559
        db 4
        dw 56675
        db 4
        dw 56905
        db 4
        dw 57096
        db 4
        dw 57325
        db 4
        dw 57478
        db 4
        dw 57631
        db 4
        dw 58050
        db 4
        dw 58165
        db 4
        dw 58280
        db 4
        dw 58624
        db 4
        dw 58815
        db 4
        dw 59082
        db 4
        dw 59463
        db 4
        dw 59616
        db 4
        dw 59845
        db 4
        dw 60074
        db 4
        dw 60227
        db 4
        dw 60646
        db 4
        dw 61065
        db 4
        dw 61484
        db 4
        dw 61599
        db 4
        dw 61904
dira:
        db 6
        dw 49288
        db 6
        dw 49290
        db 6
        dw 49292
        db 6
        dw 49294
        db 6
        dw 49296
        db 6
        dw 49298
        db 6
        dw 50976
        db 6
        dw 52396
        db 6
        dw 52913
        db 6
        dw 53689
        db 6
        dw 54336
        db 6
        dw 54854
        db 6
        dw 55371
        db 6
        dw 55888
        db 6
        dw 56664
        db 6
        dw 57181
        db 6
        dw 57569
        db 6
        dw 58215
        db 6
        dw 58475
        db 6
        dw 58863
        db 6
        dw 59638
        db 6
        dw 60929
        db 6
        dw 61317
        db 6
        dw 61834
        db 6
        dw 62480
        db 6
        dw 63255
        db 6
        dw 63901
        db 6
        dw 64547
        db 6
        dw 64935
        db 1
        dw 49288
        db 1
        dw 49934
        db 1
        dw 50451
        db 1
        dw 51226
        db 1
        dw 52775
        db 1
        dw 53421
        db 1
        dw 54067
        db 1
        dw 54584
        db 1
        dw 55230
        db 1
        dw 56134
        db 1
        dw 56780
        db 1
        dw 57168
        db 1
        dw 57814
        db 1
        dw 58203
        db 1
        dw 58979
        db 1
        dw 59625
        db 1
        dw 60400
        db 1
        dw 60917
        db 1
        dw 61434
        db 1
        dw 62854
        db 1
        dw 63242
        db 1
        dw 63630
        db 1
        dw 64793
        db 3
        dw 49288
        db 3
        dw 50192
        db 3
        dw 51483
        db 3
        dw 52000
        db 3
        dw 52775
        db 3
        dw 53550
        db 3
        dw 54067
        db 3
        dw 55487
        db 3
        dw 56907
        db 3
        dw 58327
        db 3
        dw 58715
        db 3
        dw 59748
codeend:
textbuf equ codeend             ; 256 bytes: BASIC POKEs the text here
wbuf0   equ textbuf+256
wbuf    equ wbuf0+4             ; 260: the normalised text
allbuf  equ wbuf+260            ; 512: allophone codes
bufend  equ allbuf+512

        org 48384
aytab:
        db 0,0,0,0,1,0,2,0,2,0,1,1,1,3,1,3
        db 4,4,4,1,1,1,3,4,3,7,0,4,2,1,0,1
        db 3,5,5,5,8,2,1,2,0,1,1,1,6,0,3,5
        db 4,4,0,0,2,1,2,3,7,6,5,5,0,5,0,6
        db 1,1,5,8,6,5,10,0,0,6,1,1,5,3,5,3
        db 8,2,4,4,0,0,0,8,1,5,10,6,4,8,2,8
        db 4,0,7,9,7,9,0,4,6,5,7,0,1,9,3,7
        db 2,3,4,0,1,9,1,7,5,8,7,12,13,2,5,10
        db 6,8,9,8,10,3,4,8,3,4,6,5,10,6,7,9
        db 0,10,2,4,8,5,5,6,6,9,10,7,9,0,8,2
        db 3,14,5,10,6,12,9,9,7,12,0,1,2,10,10,5
        db 13,6,15,12,9,7,12,12,15,11,14,14,15,8,15,10
        db 10,14,14,15,15,13,13,14,12,12,13,13,15,15,9,15
        db 15,12,14,14,11,11,14,15,14,15,10,15,15,13,13,15
        db 13,14,14,12,12,14,15,14,15,11,15,15,13,13,14,14
        db 15,15,14,12,15,15,13,15,15,14,14,15,14,15,15,15
        db 0,0,0,1,1,3,2,2,5,2,4,6,4,5,1,5
        db 5,7,6,4,6,5,5,5,6,7,7,7,4,5,0,6
        db 6,5,8,6,8,5,8,6,2,2,3,4,8,9,5,11
        db 8,6,7,3,12,12,4,9,8,7,8,5,10,6,4,6
        db 8,5,9,8,9,5,11,9,0,6,8,2,9,3,8,11
        db 13,6,12,6,7,0,1,8,2,7,10,7,10,10,6,9
        db 6,12,8,11,10,10,10,8,11,8,9,12,12,14,9,8
        db 11,11,11,10,10,9,13,9,10,12,11,14,13,11,12,12
        db 12,10,9,13,10,13,13,12,12,12,13,12,11,12,13,12
        db 14,10,14,13,12,13,14,13,14,13,11,13,12,14,13,14
        db 14,15,14,12,15,13,13,14,14,14,15,15,15,13,14,15
        db 13,15,15,13,14,15,12,15,12,14,11,14,15,15,8,14
        db 15,10,15,10,14,13,14,13,13,15,12,15,12,13,15,9
        db 15,14,12,14,14,15,11,11,15,14,15,10,15,13,15,13
        db 14,13,14,14,15,12,12,15,14,15,11,15,14,15,13,15
        db 13,14,14,15,12,15,15,13,15,14,15,14,15,14,15,15
        db 0,1,2,2,2,3,3,5,1,6,5,3,6,5,7,6
        db 6,2,6,8,7,8,8,8,8,2,8,7,9,9,10,9
        db 9,9,8,9,6,10,9,10,11,11,11,11,9,9,11,4
        db 10,11,11,12,2,4,12,10,10,11,11,12,10,12,13,12
        db 12,13,11,11,11,13,2,12,14,13,13,14,12,14,13,11
        db 6,14,10,14,14,15,15,13,15,14,10,14,13,12,15,13
        db 15,12,14,11,13,12,14,15,13,15,14,13,13,8,15,15
        db 14,14,14,15,15,14,13,15,15,13,14,3,6,15,14,12
        db 14,15,15,13,14,14,14,14,15,15,14,15,14,15,14,14
        db 14,15,14,15,15,15,14,15,14,14,15,15,15,15,15,15
        db 15,4,15,15,14,13,15,14,15,12,15,15,15,15,14,15
        db 13,15,6,14,15,15,15,12,12,14,14,11,8,15,15,15
        db 14,15,10,14,10,14,13,13,15,13,15,12,13,12,15,15
        db 9,14,14,12,15,14,15,14,11,11,15,15,10,15,13,13
        db 14,14,13,15,14,15,14,12,12,15,15,11,15,14,15,13
        db 14,13,14,15,15,12,15,15,13,15,14,14,15,15,14,15
