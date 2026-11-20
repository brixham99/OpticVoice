M128    equ 0
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
        org 45056
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
pd1:    dec a
        jr nz,pd1
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd3:    dec a
        jr nz,pd3
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd5:    dec a
        jr nz,pd5
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd7:    dec a
        jr nz,pd7
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd9:    dec a
        jr nz,pd9
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd11:    dec a
        jr nz,pd11
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd13:    dec a
        jr nz,pd13
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,1
pd15:    dec a
        jr nz,pd15
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
pd2:    dec a
        jr nz,pd2
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd4:    dec a
        jr nz,pd4
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd6:    dec a
        jr nz,pd6
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd8:    dec a
        jr nz,pd8
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd10:    dec a
        jr nz,pd10
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd12:    dec a
        jr nz,pd12
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,4
pd14:    dec a
        jr nz,pd14
        nop
        nop
        nop
        rl e
        sbc a,a
        and 16
        or b
        out ($FE),a
        ld a,3
pd16:    dec a
        jr nz,pd16
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
pd17:    dec a
        jr nz,pd17
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
pd18:    dec a
        jr nz,pd18
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
allotab:
        dw allo+0
        dw allo+2
        dw allo+4
        dw allo+6
        dw allo+8
        dw allo+10
        dw allo+505
        dw allo+924
        dw allo+1077
        dw allo+1307
        dw allo+1499
        dw allo+1653
        dw allo+1806
        dw allo+1959
        dw allo+2189
        dw allo+2342
        dw allo+2457
        dw allo+2648
        dw allo+2726
        dw allo+2841
        dw allo+3070
        dw allo+3451
        dw allo+3566
        dw allo+3719
        dw allo+3910
        dw allo+4139
        dw allo+4330
        dw allo+4521
        dw allo+4636
        dw allo+4751
        dw allo+4942
        dw allo+5095
        dw allo+5324
        dw allo+5781
        dw allo+5972
        dw allo+6163
        dw allo+6316
        dw allo+6507
        dw allo+6774
        dw allo+6965
        dw allo+7080
        dw allo+7271
        dw allo+7387
        dw allo+7617
        dw allo+7808
        dw allo+8037
        dw allo+8190
        dw allo+8343
        dw allo+8762
        dw allo+8877
        dw allo+8992
        dw allo+9336
        dw allo+9527
        dw allo+9794
        dw allo+10175
        dw allo+10328
        dw allo+10557
        dw allo+10786
        dw allo+10939
        dw allo+11358
        dw allo+11777
        dw allo+12196
        dw allo+12311
        dw allo+12616
allo:
        db 129,0,132,0,133,0,139,0,148,0,66,85,68,34,183,254
        db 202,85,100,0,9,255,253,169,42,164,0,9,191,251,181,182
        db 218,164,149,119,189,218,170,170,164,146,154,219,82,0,0,0
        db 66,17,18,111,255,254,128,0,5,255,255,245,8,33,4,34
        db 111,255,254,160,0,75,127,255,238,101,41,74,85,110,247,186
        db 162,16,136,136,128,0,66,0,137,95,255,254,128,0,2,255
        db 255,246,64,0,0,137,111,255,251,72,0,19,127,255,246,169
        db 37,41,85,110,247,186,162,0,8,136,128,0,66,0,137,95
        db 255,254,128,0,2,255,255,246,64,0,0,137,111,255,251,72
        db 0,19,127,255,246,169,73,41,85,110,247,186,162,0,8,136
        db 128,0,66,1,18,191,255,254,128,0,2,255,255,246,66,16
        db 0,4,183,255,251,32,0,38,255,255,118,218,170,146,37,93
        db 239,186,162,8,66,32,0,0,66,34,37,127,255,250,0,0
        db 19,91,119,255,253,64,0,18,219,110,255,253,145,17,45,187
        db 222,247,222,210,68,170,170,173,107,106,145,0,0,0,66,0
        db 4,191,255,251,86,64,0,5,110,247,255,251,68,34,0,4
        db 183,123,223,254,237,74,84,146,173,222,238,247,106,145,36,68
        db 68,136,64,0,66,0,68,191,255,255,252,130,32,0,4,146
        db 109,255,239,125,168,136,132,17,51,91,255,253,239,118,170,164
        db 146,82,149,109,181,173,100,136,0,0,66,0,0,55,39,255
        db 247,127,101,105,4,17,0,148,149,187,187,222,219,109,82,170
        db 74,179,91,119,119,189,221,182,170,169,36,145,17,8,66,0
        db 66,0,0,174,39,237,255,253,191,165,88,132,66,17,33,26
        db 170,219,183,123,187,182,219,109,86,170,214,173,107,91,107,90
        db 170,170,146,34,0,0,66,0,0,86,23,229,254,254,255,173
        db 233,42,66,16,130,36,74,170,182,237,222,238,247,119,109,109
        db 170,181,85,170,170,170,173,83,41,34,33,0,66,0,0,86
        db 23,229,253,255,127,183,180,149,33,8,64,146,37,153,173,187
        db 189,221,238,238,219,91,106,181,85,85,85,170,170,170,164,146
        db 33,0,65,0,0,55,23,251,255,254,215,100,34,0,2,33
        db 43,91,187,222,247,89,170,148,149,85,91,109,182,214,181,170
        db 170,148,165,85,85,42,170,181,0,66,85,68,21,255,246,37
        db 100,0,5,255,252,132,210,0,9,255,251,73,41,36,70,255
        db 254,212,148,165,85,187,221,168,132,73,74,170,64,0,0,66
        db 169,0,191,255,192,0,47,255,218,165,72,0,23,255,250,0
        db 4,219,187,191,253,64,2,191,255,106,82,148,165,93,239,100
        db 0,17,16,0,34,66,34,16,191,255,192,0,47,255,236,145
        db 16,0,23,255,250,0,2,189,247,191,253,64,4,255,255,234
        db 34,74,85,111,123,164,0,17,16,0,2,66,145,4,127,255
        db 192,0,47,255,236,145,16,0,23,255,250,0,2,189,247,191
        db 253,64,4,255,255,234,34,74,85,111,123,164,0,17,16,0
        db 8,66,144,0,191,255,128,0,95,255,111,255,160,0,47,255
        db 217,41,72,0,47,255,250,146,74,73,111,255,218,66,36,170
        db 173,187,178,0,0,0,4,66,4,166,255,255,64,0,0,6
        db 255,253,181,72,0,21,223,119,253,144,2,85,91,255,253,170
        db 169,34,43,123,221,221,164,66,34,34,17,16,0,66,1,18
        db 255,255,253,232,0,0,1,95,247,255,245,18,64,1,18,173
        db 255,189,239,106,85,73,43,118,221,238,237,106,146,72,136,146
        db 33,8,0,66,0,0,191,175,255,253,253,1,32,0,132,18
        db 246,223,253,221,236,148,136,68,146,91,183,127,253,239,118,218
        db 73,36,137,36,146,170,73,16,132,66,0,1,54,79,237,255
        db 253,223,82,210,17,8,68,136,86,85,187,187,221,187,218,219
        db 90,214,170,213,91,107,109,173,109,85,84,146,68,32,0,66
        db 0,0,154,23,229,254,254,255,173,233,42,66,16,130,36,74
        db 169,173,221,222,238,247,119,109,173,170,181,85,170,170,213,85
        db 85,73,36,66,0,66,0,0,42,23,229,255,255,127,171,116
        db 137,16,129,16,74,74,219,109,222,239,118,221,182,181,170,181
        db 154,214,181,173,107,85,82,146,34,0,0,0,67,170,144,78
        db 212,183,255,64,109,0,11,254,75,255,81,21,144,5,186,205
        db 255,181,111,105,18,238,171,190,237,91,100,68,169,36,170,64
        db 0,0,67,2,37,255,234,255,64,0,16,11,255,189,238,64
        db 2,0,45,222,238,246,146,82,74,187,239,123,218,170,164,146
        db 173,86,219,84,136,0,0,0,67,2,37,255,234,255,64,0
        db 16,11,255,223,253,128,2,0,45,222,239,122,137,82,74,187
        db 222,247,186,170,164,146,173,86,219,84,136,0,0,0,66,4
        db 74,255,245,254,128,0,72,11,255,255,253,160,2,32,150,255
        db 187,251,73,42,82,157,239,123,221,170,85,34,85,173,107,106
        db 68,0,0,0,0,133,1,52,3,250,3,248,10,143,228,142
        db 78,133,244,13,221,36,187,162,73,122,200,187,67,164,219,32
        db 221,181,10,233,86,164,218,75,106,165,53,43,1,233,18,246
        db 132,221,69,109,74,202,170,170,181,74,85,86,165,86,218,165
        db 91,85,74,173,82,154,213,42,218,148,170,205,82,183,82,86
        db 173,164,1,150,169,86,74,213,85,83,90,171,84,173,85,84
        db 171,85,90,171,109,74,148,202,73,74,173,73,85,181,42,165
        db 90,69,106,85,82,173,86,234,1,170,170,170,73,84,170,173
        db 85,91,83,53,85,168,138,212,170,149,119,110,213,84,136,68
        db 74,85,109,182,234,170,181,36,146,86,169,90,183,100,1,37
        db 109,180,74,182,212,137,109,170,164,173,181,36,166,182,169,9
        db 171,117,37,181,182,73,173,84,146,109,173,85,86,169,74,73
        db 91,187,33,45,1,86,164,171,42,212,74,183,186,144,137,189
        db 146,17,95,187,164,37,82,168,139,110,237,170,170,164,169,36
        db 173,85,85,85,85,85,85,85,85,85,0,133,1,237,0,79
        db 253,17,34,174,246,33,122,26,214,200,213,51,70,212,150,170
        db 217,85,73,91,85,82,170,170,170,170,165,85,85,85,85,85
        db 85,85,1,170,170,170,170,173,85,85,74,170,170,165,42,170
        db 204,202,85,85,90,213,85,90,214,170,170,170,179,50,148,171
        db 84,170,170,170,146,169,85,182,1,173,85,85,173,106,171,85
        db 82,170,170,169,36,166,82,153,74,181,85,84,171,90,170,173
        db 182,181,37,53,170,145,18,181,182,214,219,107,84,202,1,148
        db 170,74,85,181,107,85,109,43,85,85,145,42,86,164,150,247
        db 105,45,212,66,19,105,43,102,238,166,218,212,146,83,36,212
        db 173,102,119,86,1,164,165,41,73,90,221,212,173,170,164,85
        db 84,69,111,236,146,218,36,75,109,73,182,218,148,170,174,66
        db 186,170,170,170,170,170,170,170,170,170,0,131,66,154,203,96
        db 189,84,92,173,46,177,84,184,203,217,15,175,28,116,228,7
        db 180,90,174,89,193,226,152,241,159,3,206,49,224,252,61,27
        db 120,61,66,225,145,193,226,190,7,143,143,31,42,60,112,167
        db 27,19,133,184,88,240,252,23,200,248,15,59,141,56,184,62
        db 80,220,101,168,245,3,225,57,66,240,215,62,27,250,31,94
        db 176,215,139,78,29,14,104,123,15,194,184,199,35,47,22,229
        db 199,129,233,97,214,13,225,124,69,232,194,248,30,129,65,71
        db 147,142,212,122,202,203,138,165,84,203,53,102,171,26,208,178
        db 198,203,75,109,42,165,202,171,74,91,82,202,213,74,205,74
        db 172,202,170,170,0,66,170,170,170,170,170,82,166,85,85,85
        db 85,86,181,173,90,213,85,85,82,148,165,41,85,85,107,91
        db 109,187,187,182,218,214,170,165,36,146,68,66,36,146,73,36
        db 146,82,170,182,219,187,189,221,219,109,85,82,72,136,136,136
        db 146,85,86,219,119,123,222,247,118,219,106,170,73,36,145,17
        db 17,66,136,145,18,73,36,165,85,91,110,238,239,119,118,218
        db 204,164,146,34,34,34,73,42,171,109,221,222,247,189,221,182
        db 213,82,148,146,72,136,136,66,136,146,34,73,36,165,85,91
        db 110,238,239,119,118,218,170,146,68,68,68,73,37,85,91,110
        db 238,247,187,187,109,170,170,82,146,82,74,73,36,0,67,85
        db 72,150,164,174,254,165,253,0,149,32,23,245,45,254,201,187
        db 33,21,82,77,251,187,254,237,187,82,85,73,42,214,102,181
        db 73,17,0,0,67,0,0,95,219,255,255,253,200,8,128,4
        db 68,155,255,191,254,214,168,132,72,137,183,119,255,254,247,181
        db 85,34,36,146,85,106,170,145,16,0,67,0,0,95,219,255
        db 255,253,200,8,128,4,68,173,253,223,254,214,168,132,72,137
        db 183,119,255,247,189,213,85,36,68,164,149,106,170,145,16,0
        db 65,0,0,191,247,255,254,213,80,0,0,4,183,187,255,221
        db 182,164,2,33,21,110,239,123,221,181,85,37,41,85,85,90
        db 213,85,84,165,85,85,0,133,1,156,31,48,97,99,180,248
        db 225,208,215,151,145,56,227,100,212,248,97,140,180,216,106,57
        db 143,44,99,199,71,26,105,46,83,74,166,151,22,169,1,171
        db 77,51,50,173,82,218,85,77,74,178,154,165,102,102,165,106
        db 170,181,86,179,42,170,164,181,37,89,86,77,178,173,86,169
        db 170,173,171,106,1,91,74,169,74,164,170,165,90,182,149,210
        db 109,76,210,84,146,82,86,74,213,85,91,105,45,169,82,182
        db 137,118,149,43,178,149,106,74,173,164,1,91,82,181,90,37
        db 91,37,85,217,42,218,172,138,164,214,69,180,173,77,100,173
        db 181,85,182,66,183,176,39,180,68,223,168,154,237,4,181,109
        db 1,17,218,106,21,182,202,170,165,85,108,150,165,90,183,73
        db 108,137,73,186,137,189,182,146,181,18,146,221,85,181,172,162
        db 85,72,77,187,77,237,1,68,69,118,1,55,221,38,238,212
        db 137,168,145,27,234,110,214,210,19,34,85,107,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,0,66,85,84
        db 145,21,182,164,77,222,234,149,109,170,145,8,171,84,137,86
        db 237,170,219,189,221,182,219,118,218,170,181,170,165,42,170,164
        db 136,132,0,66,0,0,9,111,255,221,255,254,212,137,34,32
        db 0,8,170,179,91,190,251,182,221,219,85,85,86,181,170,182
        db 221,182,181,170,170,73,17,0,0,66,0,0,9,191,255,221
        db 255,254,210,34,34,32,0,137,90,214,222,251,221,181,182,213
        db 74,85,182,181,183,119,118,214,170,170,73,17,16,0,0,66
        db 0,0,47,255,255,255,220,128,2,16,132,183,255,239,125,212
        db 132,16,132,75,127,255,255,247,106,73,36,146,173,187,182,219
        db 82,68,0,0,0,0,67,153,68,38,247,218,111,217,0,5
        db 221,181,191,250,0,4,210,37,191,254,202,107,89,37,191,253
        db 214,181,170,73,85,182,170,170,145,0,0,0,67,0,68,255
        db 255,208,0,0,34,95,255,244,0,4,34,87,255,246,64,8
        db 146,183,255,253,168,136,146,173,222,251,169,16,132,73,85,72
        db 0,0,66,0,68,255,255,208,0,0,17,95,255,244,0,0
        db 2,43,255,251,16,132,34,91,255,255,106,148,136,149,191,253
        db 214,82,34,16,149,34,0,0,0,66,85,85,85,85,85,85
        db 41,85,85,85,85,86,181,107,90,213,85,85,74,82,148,165
        db 85,85,107,91,109,221,221,182,218,214,170,148,164,146,34,66
        db 145,36,137,36,146,74,170,219,109,221,222,238,237,181,85,82
        db 72,136,136,137,36,149,86,219,187,189,239,123,187,109,170,170
        db 73,36,146,34,36,66,136,146,34,73,36,165,85,109,183,119
        db 123,187,187,109,85,36,146,34,34,34,73,42,173,182,238,247
        db 189,238,238,219,85,84,164,146,68,72,136,66,136,146,34,73
        db 36,165,85,109,183,119,123,187,187,109,85,36,146,34,34,34
        db 73,42,173,182,238,247,189,238,238,219,85,82,148,146,68,72
        db 136,65,136,136,136,137,37,91,110,238,247,118,218,170,146,73
        db 37,41,85,85,85,85,85,85,107,90,214,181,173,85,85,85
        db 42,170,170,170,170,170,170,0,133,1,156,109,143,17,154,100
        db 157,51,141,186,177,198,150,180,199,22,158,178,203,101,142,78
        db 106,88,210,211,78,105,162,211,86,86,85,85,85,90,166,1
        db 85,82,170,181,37,85,86,85,181,86,170,213,85,45,82,77
        db 178,68,182,201,45,182,217,91,164,68,182,68,87,123,42,182
        db 201,16,173,36,213,0,66,170,170,170,170,153,85,85,85,85
        db 86,170,170,213,85,53,83,42,170,170,85,85,85,171,89,173
        db 107,107,90,213,106,170,170,170,83,41,41,36,66,136,194,140
        db 154,51,154,117,108,181,213,108,214,106,198,85,26,52,84,202
        db 170,171,90,182,219,86,183,77,181,153,106,180,149,42,101,74
        db 82,82,65,68,132,73,181,219,119,119,50,202,81,18,83,76
        db 213,182,213,153,169,74,83,51,53,173,107,85,85,85,42,170
        db 170,205,85,85,85,42,170,170,0,67,170,145,53,17,183,105
        db 191,164,247,32,38,128,91,17,94,233,190,210,221,164,183,82
        db 222,214,239,109,247,109,182,165,89,18,146,34,32,0,0,67
        db 0,0,25,15,229,255,255,255,173,233,42,32,132,32,146,18
        db 170,219,187,187,187,187,187,187,91,106,181,85,170,170,213,85
        db 85,73,34,32,0,67,0,0,25,15,229,255,255,255,183,217
        db 41,8,66,32,146,18,170,219,187,187,187,239,119,118,219,106
        db 181,85,170,170,170,173,83,41,17,8,0,67,0,0,25,15
        db 229,255,255,255,183,217,41,8,66,32,146,18,170,219,187,187
        db 187,239,119,118,219,106,181,85,170,170,170,173,83,41,17,8
        db 0,67,0,0,25,15,229,255,255,255,183,217,41,8,66,32
        db 146,18,170,219,187,187,187,239,119,118,219,106,181,85,170,170
        db 170,173,83,41,17,8,0,66,0,0,42,23,229,255,255,127
        db 171,184,137,16,129,16,74,37,182,238,247,189,247,119,109,107
        db 89,173,90,214,182,214,181,170,170,72,132,0,0,0,66,170
        db 68,45,213,91,255,64,109,0,11,254,75,255,81,21,144,5
        db 186,205,255,181,111,105,19,118,171,127,117,173,168,137,82,73
        db 84,128,0,0,66,0,70,255,245,254,128,0,72,11,255,255
        db 253,128,8,128,45,254,239,253,68,169,18,187,222,255,237,85
        db 82,34,173,107,109,169,34,0,0,0,66,2,37,255,234,255
        db 64,0,16,11,255,223,253,128,2,0,87,189,239,122,137,82
        db 73,110,247,119,186,170,169,18,173,86,219,84,136,0,0,0
        db 66,2,37,255,234,255,64,0,16,11,255,255,254,192,2,0
        db 155,222,239,246,146,84,146,187,222,255,237,85,82,37,85,86
        db 219,84,162,0,0,0,66,0,34,255,235,255,64,0,0,11
        db 247,127,255,82,100,0,68,73,191,251,255,212,170,164,77,219
        db 119,189,219,106,34,82,36,170,164,136,128,0,66,0,1,127
        db 203,255,106,169,0,36,2,221,221,255,213,188,130,34,33,45
        db 173,255,255,254,235,90,146,82,149,109,182,237,173,84,136,0
        db 0,0,66,0,0,95,79,253,255,253,149,64,4,0,17,36
        db 223,187,254,239,117,36,164,37,73,93,221,239,189,251,182,213
        db 73,34,34,68,73,17,17,0,66,0,0,94,79,245,255,255
        db 126,197,100,17,8,66,33,45,77,221,222,247,119,117,182,171
        db 90,205,107,91,109,182,214,182,170,169,36,68,0,0,66,0
        db 0,42,23,229,255,254,255,183,216,148,132,33,16,146,37,85
        db 109,221,223,123,222,238,237,173,170,181,85,170,170,213,85,85
        db 82,34,32,0,66,0,0,42,23,229,255,255,127,214,233,18
        db 66,17,16,74,74,214,221,239,123,221,187,109,109,170,181,154
        db 214,181,181,173,85,85,36,68,0,0,0,66,101,41,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,85,90,213,86,170,181,85,107,85,85,85,85,85,85,41
        db 74,66,82,148,170,170,170,213,85,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,90,213,86,170,181,85,107,85
        db 85,85,85,85,85,41,74,1,199,114,46,26,28,55,50,158
        db 58,109,49,230,177,78,90,86,54,82,172,172,214,42,181,85
        db 85,149,85,85,85,85,85,85,85,85,85,85,85,0,67,170
        db 164,68,173,182,170,239,123,68,34,82,136,9,91,221,171,110
        db 238,169,36,173,173,107,110,247,119,118,219,106,146,73,74,82
        db 73,17,16,0,67,0,0,18,223,255,255,247,189,237,32,0
        db 2,16,137,37,110,239,123,187,182,219,85,85,85,90,219,182
        db 221,221,219,85,84,164,145,16,0,0,67,0,0,18,223,255
        db 255,247,189,237,32,0,0,16,137,37,110,239,123,187,182,219
        db 85,85,85,86,219,109,187,187,182,213,84,164,145,16,0,0
        db 66,0,0,19,127,255,255,189,239,108,128,0,1,17,18,86
        db 239,123,221,219,107,85,82,149,86,219,119,123,222,237,181,82
        db 146,72,132,33,0,0,0,67,85,72,68,223,254,202,85,105
        db 0,2,255,253,169,42,168,128,19,119,189,214,181,173,82,149
        db 119,222,237,85,85,41,73,85,173,84,128,0,0,67,4,73
        db 95,255,254,128,0,2,255,255,237,32,0,132,68,183,255,251
        db 72,0,37,191,255,246,169,37,41,85,109,222,237,73,16,136
        db 145,16,0,67,2,36,223,255,254,128,0,5,255,255,250,132
        db 16,66,36,183,255,254,160,0,37,191,255,221,82,148,165,51
        db 91,189,237,72,65,8,136,136,0,67,2,36,223,255,254,128
        db 0,5,255,255,250,132,16,66,36,183,255,254,160,0,37,191
        db 255,221,82,148,165,51,91,189,237,72,65,8,136,136,0,67
        db 2,36,223,255,254,128,0,5,255,255,246,64,8,66,36,183
        db 255,254,160,0,19,127,255,187,82,148,165,51,91,189,237,72
        db 65,8,136,128,0,0,67,170,144,139,127,244,138,169,0,5
        db 255,246,34,169,0,9,255,251,73,41,36,75,127,251,170,82
        db 149,85,119,222,210,34,73,74,170,68,0,0,67,72,132,127
        db 255,192,0,47,255,234,73,16,0,79,255,244,0,2,119,187
        db 191,251,32,4,223,255,180,146,82,149,110,247,82,0,17,34
        db 0,34,67,36,66,127,255,192,0,47,255,245,36,136,0,23
        db 255,250,0,4,222,247,127,246,144,2,191,255,178,73,41,74
        db 187,222,210,16,136,136,66,17,67,36,66,127,255,192,0,47
        db 255,245,36,136,0,23,255,250,0,4,222,247,127,246,144,2
        db 191,255,178,73,41,74,187,222,210,16,136,136,66,17,67,36
        db 66,127,255,192,0,47,255,245,36,136,0,23,255,250,0,4
        db 222,247,127,246,144,2,191,255,178,73,41,74,187,222,210,16
        db 136,136,66,17,65,164,66,127,255,64,0,174,251,111,255,200
        db 0,43,255,182,247,168,0,38,255,247,118,218,68,74,221,218
        db 214,170,82,149,85,85,85,84,170,170,0,66,85,82,169,21
        db 82,149,169,110,171,119,83,118,77,100,149,82,85,36,170,170
        db 182,183,123,187,222,239,119,118,214,181,74,82,73,34,17,0
        db 0,66,0,0,74,11,213,221,253,191,187,221,178,170,68,144
        db 132,72,138,146,173,109,187,187,221,222,247,187,182,218,170,170
        db 146,82,74,72,136,132,32,66,0,0,74,11,213,221,253,191
        db 187,221,178,170,34,68,34,36,73,74,173,109,222,239,125,239
        db 189,219,182,181,85,76,164,165,36,164,136,132,0,66,0,0
        db 95,87,255,255,255,169,84,64,4,65,20,214,187,222,239,118
        db 169,82,73,42,181,183,123,223,123,182,178,146,36,137,41,82
        db 68,64,0,65,0,69,127,255,254,246,0,0,1,10,255,255
        db 247,186,64,1,8,75,127,255,123,221,82,82,149,85,182,219
        db 90,170,165,41,85,85,74,170,170,0,67,170,144,27,246,183
        db 254,128,11,72,11,255,161,54,64,2,255,102,255,176,4,237
        db 75,127,246,173,180,137,93,218,221,212,136,146,32,0,0,0
        db 67,149,73,127,224,9,0,0,255,230,254,128,1,125,87,255
        db 80,2,32,13,255,251,187,32,75,189,239,253,145,18,146,91
        db 221,82,72,0,0,16,67,146,164,255,224,9,0,0,255,230
        db 254,128,1,125,87,255,80,2,32,23,255,247,119,32,39,125
        db 239,253,145,18,73,91,187,82,32,0,0,8,67,146,164,255
        db 224,9,0,0,255,230,254,128,1,125,87,255,80,2,32,23
        db 255,247,119,32,39,125,239,253,145,18,73,91,187,82,32,0
        db 0,8,67,146,164,255,224,9,0,0,255,230,254,128,1,125
        db 87,255,80,2,32,23,255,247,119,32,39,125,239,253,145,18
        db 73,87,123,82,72,0,0,8,0,2,85,85,85,85,85,85
        db 85,85,82,173,42,205,106,86,210,90,164,138,236,23,210,91
        db 109,37,180,75,34,208,158,196,246,86,210,220,165,170,82,2
        db 200,173,82,23,176,23,208,190,173,212,183,38,129,244,11,208
        db 42,149,137,126,139,252,138,253,7,176,141,86,129,248,31,64
        db 118,46,141,238,3,2,162,186,165,109,72,110,9,150,203,73
        db 236,93,200,55,19,160,190,145,189,42,155,178,45,128,178,37
        db 69,120,95,162,93,213,11,232,45,182,66,0,66,101,41,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,85,85,90,213,86,170,181,85,107,85,85,85,85,85,85
        db 41,74,66,82,148,170,170,170,213,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,90,213,86,170,181,85,107
        db 85,85,85,85,85,85,41,74,1,87,64,247,149,18,170,246
        db 68,203,101,108,154,153,102,101,85,90,165,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,85,85,0,2
        db 85,85,85,85,85,85,85,85,89,85,85,85,89,149,85,85
        db 84,213,86,89,101,150,85,154,83,77,85,77,85,75,43,53
        db 44,211,84,180,181,2,173,50,197,154,141,147,148,199,54,45
        db 154,103,11,155,57,212,227,42,229,97,212,149,45,153,43,26
        db 106,173,76,185,99,84,213,140,177,103,88,2,155,89,102,210
        db 114,170,114,204,170,212,182,85,102,114,230,156,241,105,90,85
        db 106,177,165,43,233,50,101,148,155,28,177,116,116,108,86,210
        db 85,2,140,101,166,138,210,89,89,148,196,205,45,53,26,170
        db 153,149,101,84,227,98,193,213,204,213,44,170,141,82,109,198
        db 185,154,107,150,149,114,104,2,103,37,177,83,198,184,205,75
        db 50,171,50,99,101,46,57,77,81,178,55,42,149,85,86,164
        db 212,181,83,58,105,70,166,165,106,169,170,170,178,0,67,85
        db 72,137,110,237,87,126,228,0,37,36,69,127,253,170,171,82
        db 16,69,110,238,239,254,237,85,85,82,149,86,237,181,170,170
        db 68,0,0,0,67,0,34,95,255,255,178,68,64,0,2,111
        db 255,189,247,186,144,0,68,149,91,191,255,253,218,170,73,36
        db 170,219,187,182,181,82,68,0,0,0,67,0,34,95,255,255
        db 178,68,64,0,2,111,255,123,239,186,144,0,68,149,91,191
        db 255,253,218,170,73,36,170,219,187,182,181,82,68,0,0,0
        db 66,0,34,95,255,255,169,34,0,0,2,187,239,123,221,218
        db 64,0,68,146,183,127,255,221,181,85,36,73,91,119,118,219
        db 106,145,8,0,0,0,0,67,170,164,68,173,182,170,239,123
        db 68,34,82,136,9,91,221,171,110,238,169,36,171,109,86,239
        db 126,247,109,182,213,82,73,41,73,36,145,16,0,67,0,0
        db 18,223,255,255,239,123,218,136,0,0,136,137,37,110,247,187
        db 187,109,182,213,84,170,182,219,109,183,119,118,213,82,146,72
        db 136,0,0,67,0,0,18,223,255,255,247,189,237,32,0,0
        db 136,136,149,110,247,187,187,109,219,85,84,170,173,182,219,119
        db 119,109,181,82,146,72,136,0,0,67,0,0,18,223,255,255
        db 247,189,237,32,0,0,136,136,149,110,247,187,187,109,219,85
        db 84,170,173,182,219,119,119,109,181,82,146,72,136,0,0,67
        db 0,0,18,223,255,255,247,189,237,32,0,0,136,136,149,110
        db 247,187,187,109,219,85,84,170,173,182,219,119,119,109,181,82
        db 146,72,136,0,0,67,0,0,9,191,255,255,239,123,218,136
        db 0,0,68,68,149,109,222,247,119,109,182,213,84,170,173,182
        db 219,119,119,109,170,169,73,34,32,0,0,0,66,85,33,11
        db 127,244,138,212,128,5,255,252,132,210,0,9,255,251,73,41
        db 36,75,127,254,212,146,149,85,189,247,84,68,73,74,170,68
        db 0,0,66,82,32,191,255,192,0,47,255,213,84,164,0,23
        db 255,244,0,2,183,119,127,246,144,4,223,255,181,37,41,74
        db 183,123,168,132,68,68,0,17,66,136,132,127,255,192,0,47
        db 255,236,136,136,0,23,255,250,0,2,189,239,127,251,32,4
        db 223,255,217,34,74,83,93,239,100,0,137,17,0,8,66,72
        db 128,191,255,192,0,47,255,234,72,136,0,23,255,250,0,2
        db 189,239,127,251,32,2,191,255,217,17,41,74,221,239,100,0
        db 8,136,0,4,66,34,16,191,255,192,0,47,255,237,73,36
        db 0,11,255,253,0,1,55,119,127,253,144,0,175,255,237,82
        db 73,36,171,191,116,128,8,64,0,34,66,86,169,191,255,208
        db 0,11,255,253,219,89,0,0,191,255,217,8,68,73,55,255
        db 255,80,132,173,222,247,222,212,132,17,91,118,202,32,0,0
        db 66,0,8,191,255,250,0,0,37,85,191,255,236,128,0,37
        db 187,187,255,186,145,8,173,239,123,222,246,164,68,149,110,218
        db 214,170,68,0,0,0,66,0,0,159,255,255,200,0,0,0
        db 1,55,255,255,106,72,136,0,4,173,255,253,239,119,106,72
        db 137,85,183,118,238,237,84,136,132,32,0,0,66,0,0,43
        db 255,255,253,219,50,64,0,0,37,110,239,123,239,123,82,33
        db 8,146,85,110,247,255,222,238,218,164,146,34,36,148,170,164
        db 136,128,66,0,0,18,223,255,253,239,119,106,136,0,4,68
        db 146,85,187,222,247,109,107,90,170,170,170,182,219,182,221,221
        db 182,170,148,164,145,8,64,0,66,0,0,9,191,255,253,239
        db 123,218,145,0,8,66,36,149,110,247,189,219,109,182,170,170
        db 153,173,109,182,219,119,109,170,169,74,72,136,0,0,66,0
        db 0,37,191,255,251,222,247,180,136,0,17,17,36,171,123,222
        db 247,109,173,106,148,165,86,219,110,238,238,237,172,202,148,145
        db 17,8,64,0,0,66,101,41,85,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,89,171,90,170
        db 213,85,107,85,85,85,85,85,85,41,74,65,82,148,170,170
        db 170,213,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,85,90,213,86,170,181,85,107,85,85,85,85,85,85,41
        db 74,1,181,193,172,56,101,57,201,113,150,60,89,112,229,139
        db 77,43,148,228,230,53,89,82,214,77,106,89,85,85,85,85
        db 85,85,85,85,85,85,85,66,170,164,170,146,74,169,38,213
        db 85,173,85,182,170,181,170,170,170,82,170,165,90,170,219,109
        db 187,187,183,118,219,109,85,82,146,72,132,33,8,65,8,66
        db 95,255,255,255,98,17,0,1,45,221,239,253,170,72,132,33
        db 42,221,223,254,237,181,73,36,171,90,219,109,85,41,74,101
        db 42,170,181,0,66,101,41,85,85,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,89,171,90,170,213
        db 85,107,85,85,85,85,85,85,41,74,65,82,148,170,170,170
        db 213,85,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,90,213,86,170,181,85,107,85,85,85,85,85,85,41,74
        db 1,60,139,216,31,240,5,251,9,91,65,110,228,47,168,157
        db 164,109,53,169,50,173,84,154,173,164,173,82,213,86,82,181
        db 84,173,85,85,85,85,66,170,169,37,84,146,86,213,43,109
        db 181,86,218,165,85,170,73,85,41,74,181,154,219,110,237,221
        db 221,182,214,170,170,165,41,37,41,34,34,16,65,0,17,95
        db 255,254,201,32,0,0,157,255,251,222,210,0,0,149,187,189
        db 239,118,146,36,170,219,187,187,106,164,148,165,85,86,170,165
        db 51,53,0,66,85,85,83,42,170,170,170,170,106,170,170,170
        db 171,51,85,85,85,85,85,85,85,85,85,86,170,173,86,173
        db 109,89,170,213,106,106,101,74,73,66,163,26,84,82,74,203
        db 170,165,150,92,238,69,174,140,213,39,52,214,44,210,146,211
        db 74,205,172,214,234,173,181,180,185,173,89,82,149,81,162,66
        db 73,35,40,164,172,109,75,147,211,92,221,78,43,89,75,85
        db 70,142,194,166,77,50,170,181,173,106,221,107,108,213,102,173
        db 74,149,41,74,69,65,34,73,37,118,247,107,110,84,145,37
        db 41,85,107,93,90,170,170,84,165,85,86,181,107,85,85,84
        db 202,170,173,85,85,85,85,85,85,85,85,0,66,101,41,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,85,85,89,171,90,170,213,85,107,85,85,85,85,85,85
        db 41,74,65,82,148,170,170,170,213,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,90,213,86,170,181,85,107
        db 85,85,85,85,85,85,41,74,1,111,11,55,15,193,151,47
        db 5,240,43,216,23,148,155,178,45,112,125,22,91,73,83,232
        db 165,170,86,170,201,108,202,170,173,42,170,170,170,170,66,85
        db 73,84,75,68,181,42,219,43,185,93,169,181,82,172,146,169
        db 42,165,90,171,109,183,119,119,119,119,107,90,170,169,74,73
        db 36,68,33,4,65,0,1,63,171,255,127,246,162,36,0,136
        db 69,91,183,126,238,237,36,145,17,42,182,247,189,239,109,106
        db 146,82,148,170,170,173,85,74,170,170,0,2,85,85,85,89
        db 77,89,85,85,86,138,212,174,54,104,180,178,103,145,107,147
        db 198,55,21,112,222,28,44,203,208,218,51,196,71,194,188,49
        db 197,2,167,83,83,198,23,128,190,28,120,241,120,107,225,227
        db 236,31,66,215,7,148,63,15,88,60,117,22,140,254,15,12
        db 120,227,224,63,7,176,240,2,196,126,0,126,35,196,242,206
        db 18,254,15,10,120,177,99,208,120,124,30,96,236,31,140,120
        db 120,135,131,195,15,56,120,225,109,75,132,89,227,2,124,83
        db 163,225,130,244,154,11,92,29,112,30,142,192,253,15,130,63
        db 129,119,143,192,56,31,140,108,223,144,246,31,48,248,29,199
        db 30,3,224,2,103,88,237,1,238,55,152,244,241,227,240,199
        db 131,182,31,8,248,31,209,207,135,199,205,44,125,199,141,248
        db 49,192,254,12,191,14,49,154,67,2,184,103,168,215,7,240
        db 123,143,168,61,179,200,137,176,248,183,240,191,195,240,222,13
        db 116,31,203,52,47,3,244,15,65,226,115,7,131,238,26,1
        db 161,92,55,89,155,9,244,143,7,114,77,105,52,93,46,39
        db 37,232,173,43,137,116,106,83,101,46,149,201,105,46,149,105
        db 57,77,85,85,85,0,66,106,170,170,85,85,89,45,82,217
        db 89,90,149,86,106,180,93,41,170,101,170,165,101,105,203,85
        db 171,77,173,86,91,43,49,106,197,74,150,34,66,131,180,31
        db 68,120,14,97,237,30,8,224,158,26,226,225,15,33,71,142
        db 168,211,165,246,15,211,90,107,196,182,142,195,106,141,92,89
        db 71,74,66,193,142,96,233,56,136,238,47,129,249,62,25,101
        db 208,184,121,33,225,53,209,203,86,150,233,56,61,143,67,185
        db 26,46,92,162,244,89,44,58,66,135,68,60,27,147,174,134
        db 118,55,199,142,160,226,142,30,44,120,244,15,70,204,95,10
        db 218,122,55,103,67,108,212,46,46,74,209,168,172,81,66,201
        db 26,42,30,57,167,201,75,216,120,146,208,155,99,244,212,90
        db 57,211,18,170,55,25,233,167,201,205,53,35,102,77,54,154
        db 181,82,76,136,0,66,85,84,145,21,182,164,77,222,234,149
        db 109,170,145,8,171,84,137,86,237,170,219,189,221,182,219,118
        db 218,170,214,170,169,85,82,148,136,132,0,66,0,0,9,111
        db 255,187,255,254,212,137,34,32,0,8,170,170,182,247,187,182
        db 221,219,85,85,86,181,170,182,221,182,181,170,170,72,136,128
        db 0,66,0,0,39,255,238,255,253,164,0,34,0,9,189,247
        db 189,239,105,34,34,36,149,222,251,223,123,218,165,36,146,85
        db 86,218,214,170,64,0,0,0,2,170,170,170,170,170,170,170
        db 170,172,178,179,42,172,170,179,42,178,171,77,53,77,38,199
        db 29,45,45,42,173,101,86,139,43,84,182,152,217,57,2,73
        db 81,172,49,102,100,177,180,244,228,117,201,28,156,103,18,228
        db 166,214,199,69,150,78,173,11,84,179,74,177,78,139,28,212
        db 179,150,41,173,2,196,154,92,166,154,178,90,213,49,105,149
        db 184,117,60,164,209,83,53,166,153,202,184,154,76,117,139,41
        db 202,167,44,89,53,164,230,117,82,169,2,21,217,145,182,84
        db 179,139,87,22,54,81,57,173,66,211,165,98,219,41,198,172
        db 165,163,26,91,42,169,186,89,211,96,113,114,195,170,107,153
        db 2,172,212,153,211,71,70,89,172,106,152,232,180,206,50,85
        db 102,211,26,92,229,74,171,38,88,235,39,44,177,86,170,170
        db 171,23,27,166,53,140,0,133,1,203,131,208,127,128,62,7
        db 208,47,165,149,208,219,138,244,55,161,29,90,30,73,171,42
        db 94,19,180,23,212,146,219,72,182,150,197,91,40,218,1,150
        db 74,218,77,101,53,77,169,75,101,74,208,188,141,146,170,212
        db 217,61,23,164,182,212,91,19,176,77,145,108,77,153,220,47
        db 164,186,138,208,1,92,79,68,218,221,87,116,153,11,208,173
        db 42,171,109,145,42,202,164,86,201,186,183,74,170,170,170,170
        db 170,170,170,170,170,170,170,170,170,170,0,133,1,159,65,239
        db 144,114,71,160,203,39,208,240,126,15,161,224,248,108,139,161
        db 189,15,131,194,63,135,224,124,141,39,43,74,92,157,42,201
        db 87,21,1,149,98,218,106,75,85,165,90,77,85,82,172,149
        db 210,118,75,106,200,248,30,133,228,232,188,14,196,182,149,149
        db 209,118,19,208,186,30,133,224,1,190,139,178,188,157,43,69
        db 185,27,130,224,186,47,160,190,7,209,178,232,62,130,221,5
        db 228,77,210,77,232,95,68,221,130,244,137,216,78,202,1,87
        db 73,170,228,111,66,186,147,86,193,125,11,226,105,116,55,100
        db 93,66,172,170,85,169,59,22,228,173,37,147,80,187,41,171
        db 118,39,161,116,1,91,5,232,94,139,209,59,11,210,118,134
        db 228,217,43,100,55,72,191,38,150,228,75,232,95,65,93,68
        db 151,224,127,36,95,161,55,208,95,200,1,47,161,43,114,11
        db 232,95,69,162,232,46,169,42,86,69,234,110,181,109,76,149
        db 145,33,109,53,91,170,213,85,85,85,85,85,85,85,85,85
        db 0,66,170,179,51,42,172,205,52,170,105,170,90,167,39,42
        db 169,199,39,44,113,105,165,84,213,90,171,77,92,173,86,154
        db 186,89,178,107,42,84,166,66,50,46,53,220,184,241,199,143
        db 29,46,58,240,225,135,30,57,225,228,125,140,180,157,44,210
        db 229,112,241,122,156,61,88,174,141,91,39,71,20,66,199,104
        db 142,39,100,184,114,179,113,28,120,228,220,206,138,112,88,198
        db 211,26,156,99,166,154,112,234,116,233,205,50,218,106,167,57
        db 166,53,56,66,114,200,240,113,227,206,119,12,60,112,244,203
        db 206,167,11,134,12,241,161,102,156,177,124,242,156,120,233,157
        db 172,113,198,90,142,141,57,83,13,66,120,212,121,166,231,156
        db 60,151,156,177,194,210,241,195,167,49,157,120,241,101,74,86
        db 166,205,170,213,186,89,83,22,147,42,210,182,84,169,74,0
        db 66,85,85,85,85,85,85,41,85,85,85,85,86,181,107,90
        db 213,85,85,74,82,148,165,85,85,90,219,109,183,118,219,109
        db 107,85,74,82,73,34,66,34,73,18,73,36,165,85,91,109
        db 221,221,221,219,109,85,82,73,17,17,17,36,170,170,219,187
        db 187,222,238,238,218,213,85,41,36,145,18,68,66,17,36,68
        db 146,73,74,170,181,183,119,119,119,118,218,170,169,36,68,68
        db 68,146,85,85,182,238,238,247,187,187,109,170,170,82,73,36
        db 136,137,66,17,36,68,146,73,74,170,181,183,119,119,119,118
        db 218,170,169,36,68,68,68,146,85,85,182,238,238,247,187,187
        db 109,170,170,82,73,36,136,137,66,17,36,68,146,73,74,170
        db 181,183,119,119,119,118,218,170,169,36,68,68,68,146,85,85
        db 182,238,238,247,187,187,109,170,170,82,73,36,136,137,65,17
        db 36,68,146,74,82,170,173,183,119,123,187,182,218,204,165,36
        db 68,68,146,73,85,90,214,182,219,109,173,107,85,85,85,74
        db 85,85,85,85,0,66,85,84,145,38,181,181,86,239,123,73
        db 18,101,36,68,149,109,181,173,109,219,90,171,110,219,107,109
        db 221,181,173,106,170,82,146,73,17,0,0,66,0,0,19,191
        db 255,247,123,221,81,0,0,136,137,42,239,125,238,219,106,170
        db 73,42,173,182,239,123,239,118,218,170,146,72,136,146,68,32
        db 0,66,0,0,43,255,255,189,239,116,128,0,34,34,74,221
        db 239,119,109,170,145,8,149,109,183,127,251,221,182,170,146,36
        db 148,170,170,213,34,0,0,65,0,137,127,255,251,182,64,0
        db 18,148,223,255,237,85,68,0,18,171,110,255,221,181,170,146
        db 85,90,214,219,106,170,165,41,74,170,170,170,170,0,66,85
        db 85,73,36,73,86,219,187,182,213,85,85,170,169,36,137,36
        db 170,181,182,182,219,119,123,221,221,182,181,85,85,85,41,74
        db 73,36,136,132,66,0,0,0,74,223,255,255,255,118,170,164
        db 146,33,8,33,18,86,221,222,247,119,119,119,118,219,85,85
        db 85,85,90,213,85,85,82,146,72,128,66,0,0,0,38,239
        db 255,255,238,219,85,73,34,0,0,17,42,219,189,221,219,187
        db 187,182,213,84,205,90,218,214,181,107,90,170,73,17,0,0
        db 66,0,0,79,255,255,238,238,200,0,1,18,153,183,255,251
        db 84,164,132,16,150,239,123,255,254,217,148,164,146,86,219,109
        db 182,178,136,0,0,0,0,66,170,144,78,229,55,255,64,109
        db 0,19,254,75,255,81,21,144,9,218,173,255,181,111,105,18
        db 238,171,190,237,91,100,68,169,36,170,64,0,0,66,4,74
        db 255,245,254,128,0,72,11,255,255,251,64,17,0,78,247,119
        db 253,68,169,36,183,222,255,237,85,73,18,173,86,219,85,34
        db 0,0,0,66,2,37,255,234,255,64,0,16,11,255,223,253
        db 128,2,0,45,238,239,122,137,82,74,187,221,239,118,170,164
        db 146,173,86,219,82,68,0,0,0,66,2,37,255,234,255,64
        db 0,16,11,255,223,253,128,2,0,45,222,238,246,73,82,74
        db 187,221,239,118,170,164,137,90,205,187,82,68,0,0,0,66
        db 2,37,255,245,255,64,0,36,5,255,239,253,160,2,32,39
        db 123,222,251,164,149,36,174,251,221,238,213,41,36,166,181,91
        db 106,145,0,0,0,66,1,18,255,253,191,208,0,4,64,191
        db 254,239,114,0,17,8,111,255,189,247,72,149,82,174,254,247
        db 189,169,36,164,146,182,213,84,128,0,0,66,0,4,191,255
        db 111,250,0,0,68,75,255,251,119,168,0,8,146,91,255,239
        db 123,169,18,85,107,119,187,187,106,146,34,73,74,170,144,0
        db 0,66,0,1,63,255,210,255,64,0,68,68,223,255,236,173
        db 144,0,18,170,183,255,253,219,109,34,42,219,110,247,221,85
        db 82,68,33,41,16,2,16,66,0,0,159,255,228,95,232,0
        db 19,82,43,255,253,164,148,128,0,157,218,223,255,246,171,106
        db 72,149,187,221,187,221,82,34,72,132,33,0,0,66,0,1
        db 47,255,232,151,244,0,5,178,77,255,253,169,18,72,0,78
        db 246,219,255,246,170,181,73,37,110,247,110,238,210,34,72,132
        db 32,0,0,66,0,2,95,255,233,47,232,0,10,169,45,255
        db 254,200,146,144,1,45,218,223,255,221,170,170,164,74,239,118
        db 239,118,164,145,17,16,132,0,0,0,2,170,170,170,170,170
        db 149,85,85,173,85,85,74,170,170,181,85,84,165,85,85,106
        db 170,169,74,170,170,170,171,90,214,170,170,82,170,182,219,90
        db 2,149,109,182,238,219,85,74,82,165,42,169,85,51,86,182
        db 214,181,170,82,68,68,149,85,85,85,73,37,85,109,182,213
        db 85,85,85,85,85,36,2,219,85,74,82,73,36,146,149,85
        db 109,187,182,218,170,82,170,170,170,82,170,181,173,170,169,36
        db 146,74,85,173,109,181,85,74,84,165,41,36,0,66,85,82
        db 169,21,82,149,169,110,171,119,85,186,77,101,37,82,85,36
        db 170,170,182,183,123,189,238,247,187,118,214,181,74,164,137,34
        db 17,0,0,66,0,0,74,11,213,221,253,191,187,221,178,170
        db 68,136,68,68,74,146,170,219,119,189,251,223,123,187,182,218
        db 170,170,146,82,74,72,136,132,32,66,0,0,95,75,255,255
        db 255,212,169,0,4,64,74,173,221,239,119,109,73,41,34,86
        db 219,189,247,189,238,178,148,146,36,165,85,85,34,0,0,0
        db 132,1,165,90,165,26,113,199,232,238,15,74,157,15,1,207
        db 7,146,62,46,92,127,131,244,156,133,124,51,224,179,175,1
        db 126,3,250,28,222,17,120,1,120,63,193,231,150,15,15,37
        db 94,65,220,60,225,248,31,11,134,30,45,193,231,67,220,14
        db 39,195,223,12,41,227,135,249,28,118,193,208,60,1,135,194
        db 63,129,200,62,52,248,107,200,121,151,41,169,114,31,134,84
        db 112,79,132,120,222,99,179,224,253,142,30,206,120,238,72,155
        db 15,39,131,1,151,135,34,63,6,241,211,207,5,228,248,11
        db 135,194,176,92,57,195,128,167,46,13,197,71,194,113,250,140
        db 124,224,31,15,44,121,193,248,121,1,195,245,120,60,112,232
        db 242,177,134,235,2,62,88,112,240,62,7,198,88,61,76,113
        db 248,28,248,41,215,43,10,127,39,30,49,222,7,72,252,1
        db 15,193,244,51,96,142,24,112,213,158,19,219,140,252,233,30
        db 43,124,63,3,224,191,129,248,14,180,112,60,17,124,77,199
        db 152,63,39,128,248,1,127,141,28,195,192,31,30,104,120,60
        db 41,250,30,205,70,56,129,229,162,166,62,206,80,255,5,180
        db 115,227,240,123,151,141,163,213,70,63,31,1,49,99,147,163
        db 139,80,120,65,224,185,15,70,152,181,200,241,30,133,129,248
        db 135,232,216,240,122,140,56,240,126,17,244,39,165,28,30,37
        db 195,1,169,27,193,206,30,88,183,14,15,160,244,150,169,105
        db 220,89,212,119,68,228,181,149,83,85,147,85,77,77,147,164
        db 213,89,85,85,85,85,85,0,67,85,72,35,125,146,223,251
        db 0,21,160,2,255,246,171,189,160,4,170,68,91,255,221,223
        db 186,145,42,213,85,222,246,170,170,68,33,0,0,0,67,0
        db 8,175,255,244,87,216,0,19,178,77,255,253,164,146,72,0
        db 77,238,183,255,246,170,181,72,149,110,247,110,238,210,34,72
        db 132,32,0,0,67,0,8,175,255,244,79,244,0,19,178,77
        db 255,253,164,146,72,0,77,238,183,255,246,170,181,72,149,110
        db 247,110,238,210,34,36,68,32,0,0,67,0,8,175,255,244
        db 79,244,0,19,178,77,255,253,164,146,72,0,77,238,183,255
        db 246,170,181,72,149,110,247,110,238,210,34,36,68,32,0,0
        db 65,0,4,95,255,233,191,208,0,2,86,173,255,250,146,169
        db 0,8,173,182,223,253,218,171,50,146,154,218,214,181,170,169
        db 85,41,85,74,170,181,0,67,85,72,35,125,146,223,251,0
        db 21,160,2,255,246,171,189,160,4,170,68,91,255,221,223,186
        db 145,42,213,85,189,238,101,85,68,33,0,0,0,67,0,1
        db 47,255,244,79,244,0,5,178,77,255,253,164,146,72,0,77
        db 238,219,255,246,170,181,73,37,110,247,110,238,210,34,72,132
        db 32,0,0,67,0,8,175,255,244,79,244,0,5,178,77,255
        db 253,164,146,72,0,77,238,183,255,246,170,181,72,149,110,247
        db 110,238,210,34,72,132,32,0,0,67,0,8,175,255,244,79
        db 244,0,5,178,77,255,253,164,146,72,0,77,238,183,255,246
        db 170,181,72,149,110,247,110,238,210,34,72,132,32,0,0,67
        db 0,8,175,255,244,79,244,0,5,178,77,255,253,164,146,72
        db 0,77,238,183,255,246,170,181,72,149,110,247,110,238,210,34
        db 72,132,32,0,0,67,0,8,175,255,244,79,244,0,5,178
        db 77,255,253,164,146,72,0,77,238,183,255,246,170,181,72,149
        db 110,247,110,238,210,34,72,132,32,0,0,67,0,8,175,255
        db 244,79,244,0,5,178,77,255,253,164,146,72,0,77,238,183
        db 255,246,170,181,72,149,110,247,110,238,210,34,36,68,32,0
        db 0,0,66,170,162,18,183,189,171,110,234,0,4,222,235,93
        db 255,218,33,9,85,41,157,255,255,106,170,170,169,85,187,222
        db 213,85,41,34,33,8,64,0,66,0,4,111,255,255,208,0
        db 0,34,74,223,255,255,168,0,0,137,86,238,255,255,237,36
        db 68,171,109,221,239,119,89,34,17,18,85,36,64,0,66,0
        db 1,47,255,255,228,0,0,17,42,183,255,255,100,0,0,74
        db 173,183,127,255,117,72,137,85,183,119,119,187,106,68,34,36
        db 170,145,0,0,66,0,1,47,255,255,228,0,0,17,42,183
        db 255,255,100,0,0,74,173,183,127,255,117,72,137,85,183,119
        db 119,187,106,68,34,36,170,145,0,0,66,0,1,47,255,255
        db 228,0,0,17,42,183,255,255,100,0,0,74,173,183,127,255
        db 117,72,137,85,183,119,119,187,106,68,34,36,170,145,0,0
        db 66,0,1,47,255,255,228,0,0,17,37,91,255,255,217,0
        db 1,18,85,183,127,255,246,169,18,74,182,219,187,222,235,36
        db 68,68,146,34,0,0,66,16,132,87,255,255,242,0,0,132
        db 33,19,127,255,237,72,132,33,8,137,91,255,255,187,106,170
        db 164,146,85,187,187,182,170,164,145,0,0,0,66,0,0,151
        db 255,255,253,164,66,0,0,0,77,255,255,239,119,106,68,0
        db 8,171,119,191,255,255,187,84,146,34,73,37,85,109,181,148
        db 64,0,66,0,0,5,127,255,255,119,109,170,32,0,8,149
        db 85,91,189,247,187,85,41,85,85,42,182,238,247,189,221,182
        db 170,164,146,36,145,16,132,0,66,0,0,37,191,255,253,239
        db 123,170,32,0,17,17,37,53,222,251,221,182,181,85,82,149
        db 91,109,221,221,221,219,89,148,164,146,34,33,8,0,0,66
        db 170,170,170,85,85,85,85,85,85,85,85,170,170,170,181,50
        db 170,150,101,85,85,85,106,205,107,90,214,182,181,89,170,178
        db 169,82,148,164,146,66,161,50,82,83,156,181,157,109,91,157
        db 44,231,74,170,100,202,165,44,210,83,106,171,171,110,117,181
        db 181,172,214,90,170,82,170,105,50,105,20,66,34,168,149,140
        db 210,213,157,147,216,217,179,141,170,99,76,210,100,202,140,205
        db 106,173,109,109,181,110,171,107,86,154,170,149,42,149,41,82
        db 146,65,146,37,20,82,213,86,182,173,205,173,170,155,76,170
        db 85,42,85,42,170,170,170,170,214,170,214,106,205,85,85,85
        db 85,85,82,170,170,170,170,0,2,170,170,172,204,170,180,173
        db 42,210,204,108,169,170,203,46,56,166,89,177,199,44,202,172
        db 186,37,196,230,150,143,59,142,60,120,179,155,38,54,2,109
        db 37,241,131,131,7,7,11,62,26,29,46,159,199,12,187,172
        db 56,102,56,120,224,112,227,120,243,156,230,92,177,199,19,7
        db 35,142,62,49,2,198,175,30,58,52,199,51,195,167,9,195
        db 146,112,225,198,194,116,201,227,78,53,241,35,83,35,211,61
        db 101,198,28,60,120,114,143,50,140,97,2,104,220,112,242,206
        db 14,28,112,232,163,158,88,195,193,199,15,23,24,39,20,227
        db 135,16,193,231,14,60,67,200,88,227,53,108,118,140,166,56
        db 2,206,56,109,60,92,56,177,193,195,116,92,199,12,118,93
        db 230,60,120,48,206,185,56,199,26,44,123,80,235,157,49,227
        db 42,177,98,222,60,30,2,227,142,56,240,220,248,224,251,59
        db 71,198,84,231,134,14,88,198,227,155,39,71,142,60,99,143
        db 62,21,150,112,114,78,204,243,9,199,28,44,0,66,85,85
        db 85,85,85,85,41,85,85,85,85,86,181,107,90,213,85,85
        db 74,82,148,165,85,85,90,219,109,183,118,219,109,107,85,74
        db 82,73,17,66,34,73,18,73,36,165,85,91,109,221,221,221
        db 219,109,85,82,73,17,17,18,73,42,171,109,187,187,222,238
        db 238,218,213,85,41,36,146,68,34,66,17,36,68,146,73,74
        db 170,182,219,119,123,187,182,218,170,169,36,68,68,68,146,85
        db 85,182,238,239,123,221,221,181,170,170,82,73,36,136,137,66
        db 17,36,68,146,73,74,170,181,183,119,123,187,182,218,170,169
        db 36,68,68,68,146,85,85,182,238,239,123,221,221,181,170,170
        db 82,73,36,136,137,66,17,36,68,146,73,74,170,181,183,119
        db 123,187,182,218,170,169,36,68,68,68,146,85,85,182,238,239
        db 123,221,221,181,170,170,82,73,36,136,137,65,34,34,36,146
        db 74,82,170,182,219,119,123,187,182,219,85,73,36,68,68,146
        db 82,170,170,214,219,109,182,181,173,85,85,85,74,85,85,85
        db 85,0,2,170,170,170,170,170,170,170,170,170,170,170,170,170
        db 170,170,165,90,213,84,170,182,201,36,173,213,42,173,181,36
        db 75,118,169,37,110,218,145,36,2,84,165,91,84,164,155,106
        db 146,74,221,218,169,38,165,81,42,183,118,82,68,173,183,105
        db 8,146,189,181,172,146,164,150,213,189,172,164,148,165,2,106
        db 183,85,106,146,73,187,85,37,51,85,74,173,219,89,74,73
        db 36,149,110,255,236,132,32,149,85,107,127,187,72,2,37,181
        db 109,187,186,162,1,68,187,85,85,187,106,145,43,89,74,170
        db 219,106,85,37,82,148,219,109,181,73,34,73,86,182,218,170
        db 170,169,74,170,181,85,85,85,85,86,0,66,85,68,34,183
        db 254,202,85,100,0,9,255,253,169,42,162,0,18,223,251,181
        db 173,181,82,85,189,247,182,170,170,146,73,85,182,169,0,0
        db 0,66,136,146,111,255,254,128,0,5,255,255,236,132,16,132
        db 34,111,255,254,160,0,75,127,255,221,101,37,41,85,91,222
        db 246,145,16,136,136,136,0,66,2,36,223,255,254,128,0,2
        db 255,255,237,32,0,33,9,111,255,254,160,0,19,127,255,221
        db 169,36,165,42,219,189,237,81,8,68,68,64,0,66,2,36
        db 223,255,254,128,0,2,255,255,237,32,0,33,9,111,255,254
        db 160,0,19,127,255,221,169,36,165,42,219,189,237,81,8,68
        db 68,64,0,66,2,36,223,255,254,128,0,5,255,255,218,146
        db 34,0,8,175,255,251,72,0,75,127,253,221,221,170,68,73
        db 93,247,186,146,33,17,16,0,0,66,34,73,95,255,253,0
        db 0,21,255,239,127,253,144,0,4,239,254,237,182,169,34,37
        db 187,255,221,170,170,148,146,173,187,109,73,17,0,0,0,66
        db 17,18,191,255,250,0,0,136,66,111,255,253,33,8,66,17
        db 55,255,253,170,172,201,36,183,255,221,219,106,146,34,85,107
        db 85,85,32,0,0,66,0,1,63,255,244,146,144,0,0,191
        db 253,223,254,210,0,2,82,75,127,255,221,173,84,145,43,119
        db 187,189,219,82,68,73,36,148,164,64,0,66,0,2,95,255
        db 233,47,244,0,5,106,171,127,255,98,18,144,0,43,187,187
        db 255,251,84,170,169,37,111,123,182,219,84,136,146,68,66,16
        db 132,66,0,8,175,255,233,27,244,0,5,178,77,255,254,212
        db 146,72,0,151,118,219,255,237,85,106,164,74,219,187,182,237
        db 169,34,73,16,132,32,132,66,0,34,95,255,232,155,232,0
        db 10,169,45,255,253,164,146,144,1,45,218,223,255,238,213,85
        db 73,37,187,182,238,237,82,73,34,34,16,66,0,0,66,85
        db 33,11,127,244,138,212,128,5,255,252,132,210,0,9,255,251
        db 73,41,36,75,127,254,212,146,149,85,189,247,84,68,73,74
        db 170,68,0,0,66,82,32,191,255,192,0,47,255,213,84,164
        db 0,23,255,244,0,2,183,119,127,246,144,4,223,255,181,37
        db 41,74,183,123,168,132,68,68,0,17,66,136,132,127,255,192
        db 0,47,255,236,136,136,0,23,255,250,0,2,189,239,127,251
        db 32,4,223,255,217,34,74,83,93,239,100,0,137,17,0,8
        db 66,72,128,191,255,192,0,47,255,234,72,136,0,23,255,250
        db 0,2,189,239,127,251,32,4,223,255,217,17,41,74,221,239
        db 100,0,8,136,0,4,66,34,16,191,255,192,0,47,255,218
        db 181,144,0,11,255,252,128,2,85,86,255,254,160,2,111,255
        db 119,109,81,4,86,247,106,66,16,0,0,37,66,53,34,127
        db 255,64,0,95,255,187,255,208,0,6,255,247,109,105,0,9
        db 191,255,218,170,146,36,223,255,218,146,72,137,43,119,105,0
        db 0,1,66,0,69,127,255,160,0,1,0,159,255,253,0,8
        db 128,10,255,255,82,34,33,18,223,255,221,170,164,136,150,247
        db 221,181,73,8,33,8,32,132,66,8,69,127,255,208,4,64
        db 0,11,255,251,187,236,0,1,43,90,223,254,212,149,85,37
        db 91,189,221,182,218,146,36,170,170,171,106,64,0,0,66,0
        db 0,159,255,244,175,176,0,9,181,86,255,255,81,9,32,1
        db 46,247,119,255,251,74,85,73,42,222,247,109,219,82,34,34
        db 68,33,4,32,66,65,8,175,255,244,87,216,0,11,106,77
        db 255,254,212,146,72,0,151,118,219,255,237,85,106,164,74,219
        db 187,183,118,169,34,73,16,132,33,8,66,0,34,95,255,232
        db 155,232,0,10,169,45,255,253,164,74,144,1,45,218,223,255
        db 238,213,85,72,149,187,182,238,237,82,73,34,34,16,66,0
        db 0,66,170,145,53,18,219,105,191,164,247,33,22,128,91,17
        db 94,229,127,169,187,82,183,73,187,107,189,215,123,173,182,165
        db 84,146,164,68,68,0,0,66,0,0,45,23,213,255,255,127
        db 103,114,36,128,1,16,148,138,214,219,189,239,187,221,187,182
        db 181,170,181,85,172,205,106,173,85,73,34,16,0,66,0,0
        db 154,23,229,255,254,255,173,234,84,132,33,16,146,19,85,91
        db 187,190,247,189,221,219,109,170,181,85,170,170,213,85,85,73
        db 34,33,0,66,0,0,154,23,229,255,254,255,173,234,84,132
        db 33,16,146,19,85,91,187,190,247,189,221,219,109,170,181,85
        db 170,170,213,85,85,73,34,33,0,66,0,0,42,23,234,255
        db 255,127,235,117,9,32,132,32,138,146,219,110,247,189,238,221
        db 218,219,85,107,85,107,90,214,181,170,170,73,17,0,0,66
        db 0,0,55,151,255,127,251,182,212,0,128,1,8,75,109,183
        db 187,189,218,181,148,170,169,91,182,239,123,221,219,90,164,146
        db 68,66,16,128,0,66,0,0,47,245,255,245,191,98,8,64
        db 1,42,74,255,119,191,117,74,72,132,170,171,189,239,255,187
        db 182,170,68,146,73,85,85,85,34,0,0,66,0,1,63,255
        db 255,255,64,8,0,1,43,119,127,255,106,218,64,0,136,150
        db 255,255,255,247,84,146,72,137,109,187,187,182,169,34,0,0
        db 0,66,0,34,191,255,228,111,208,0,18,136,87,255,253,170
        db 170,64,1,54,169,191,255,187,110,213,17,42,219,110,247,221
        db 82,146,33,8,64,0,0,66,0,2,95,255,242,47,244,0
        db 11,105,21,255,255,100,73,32,0,151,123,111,255,253,170,179
        db 36,74,221,238,238,238,210,34,36,66,0,0,0,66,0,8
        db 175,255,242,55,232,0,19,82,87,255,255,100,74,64,0,87
        db 109,191,255,251,85,106,146,74,238,238,239,118,164,145,17,8
        db 64,0,0,0,66,101,41,85,85,85,85,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,90,213,86,170,181
        db 85,107,85,85,85,85,85,85,41,74,66,82,148,170,170,170
        db 213,85,85,85,85,85,85,85,85,85,85,85,85,85,85,85
        db 85,90,213,86,170,181,85,107,85,85,85,85,85,85,41,74
        db 1,197,222,23,160,185,160,116,226,135,241,46,194,220,146,230
        db 168,186,87,34,217,86,164,181,170,77,170,85,85,169,85,89
        db 169,85,85,85,85,85,0,66,85,34,21,219,85,191,242,17
        db 41,0,13,255,107,127,216,130,42,65,22,255,187,191,246,146
        db 170,169,86,247,182,219,89,34,36,136,0,0,0,66,0,0
        db 191,255,247,123,64,0,4,73,191,255,219,90,64,0,18,170
        db 223,255,221,219,84,146,86,219,187,222,237,85,72,132,73,72
        db 132,32,0,66,0,2,127,255,253,239,64,0,4,136,223,255
        db 237,182,144,0,69,41,174,255,254,238,218,146,74,173,109,223
        db 123,181,84,136,132,68,64,0,0,66,0,8,191,255,254,239
        db 100,0,0,68,149,111,255,246,214,164,64,8,146,173,223,255
        db 255,187,181,73,18,85,85,182,221,218,170,145,0,0,0,66
        db 0,0,79,255,255,255,255,105,0,0,1,8,149,223,255,222
        db 238,213,16,65,18,171,110,255,255,253,221,181,82,34,34,36
        db 165,42,164,136,0,66,0,0,21,223,255,254,247,238,164,0
        db 0,132,34,85,189,247,189,219,109,82,73,42,173,182,239,125
        db 247,187,109,85,73,17,18,68,68,32,0,66,0,0,21,223
        db 255,247,123,238,164,0,0,68,68,149,187,189,221,219,109,82
        db 73,42,173,183,119,190,251,221,181,85,73,17,17,36,68,0
        db 0,65,0,0,23,255,255,251,223,114,0,0,33,8,150,239
        db 254,238,237,100,136,68,170,214,221,239,119,109,85,84,165,41
        db 85,85,86,170,169,85,85,0,66,101,41,85,85,85,85,85
        db 85,85,85,85,85,85,85,85,85,85,85,85,85,85,85,89
        db 171,90,170,213,85,107,85,85,85,85,85,85,41,74,65,82
        db 148,170,170,170,213,85,85,85,85,85,85,85,85,85,85,85
        db 85,85,85,85,85,90,213,86,170,181,85,107,85,85,85,85
        db 85,85,41,74,1,203,43,184,147,108,78,234,74,74,237,148
        db 149,109,85,84,170,170,213,74,106,170,170,170,170,170,170,170
        db 170,170,170,170,170,170,170,170,170,170,66,170,169,74,73,42
        db 170,148,170,181,173,107,85,90,214,170,169,85,85,84,165,85
        db 90,219,109,183,119,119,118,219,90,213,41,74,72,136,66,16
        db 65,128,1,63,255,254,247,178,0,1,16,138,239,123,187,186
        db 144,130,17,37,111,125,239,123,180,146,74,170,173,182,213,85
        db 84,165,41,85,85,90,0
dirb    equ allotab
dira    equ allotab
codeend:
textbuf equ codeend             ; 256 bytes: BASIC POKEs the text here
wbuf0   equ textbuf+256
wbuf    equ wbuf0+4             ; 260: the normalised text
allbuf  equ wbuf+260            ; 512: allophone codes
bufend  equ allbuf+512


