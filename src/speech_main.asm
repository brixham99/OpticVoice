; =====================================================================
; OpticOS Speech - phase 1: a software text-to-speech synthesiser for the
; 48K Spectrum running OpticOS. Text -> NRL letter-to-sound rules ->
; SP0256-style allophone codes -> pre-synthesised 1-bit allophones played
; through the beeper (port $FE bit 4) at 31,250 bits a second (112 T each).
; tools/gen.py turns this file into speech.asm (the timing code and the
; tables) and assembles it.  CLEAR 45055 first.
;
;   45056  n = USR 45056   say the text at TEXTPTR (0 or 13 ends it)
;   45059  n = USR 45059   say the allophone list at LISTPTR ($FF ends it)
;   45062  n = USR 45062   convert only: text at TEXTPTR -> allophone list
;                          at ALLBUF ($FF ends it)
;   n = the number of allophones.  45065 TEXTPTR, 45067 LISTPTR (DPOKE),
;   45069 ALLBUF address, 45071 TEXTBUF address (read only)
; =====================================================================
BORDCR  equ $5C48
;@ORG
        jp say_text
        jp say_list
        jp convert
TEXTPTR: dw textbuf
LISTPTR: dw allbuf
        dw allbuf
        dw textbuf
        db "SP"                 ; 45073: signature, so BASIC can tell the code is loaded

say_text:
        call convert
        push bc
        ld hl,allbuf
        call play
        pop bc
        ret
say_list:
        ld hl,(LISTPTR)
        push hl
        ld bc,0
sl_cnt: ld a,(hl)
        inc hl
        inc a
        jr z,sl_go
        inc bc
        jr sl_cnt
sl_go:  pop hl
        push bc
        call play
        pop bc
        ret

; ---------------------------------------------------------------------
; play: HL = allophone codes, $FF ends.  Interrupts are off while it plays.
play:   di
        ld (qptr),hl
        ld a,(BORDCR)
        rra
        rra
        rra
        and 7
        ld b,a                  ; B = border colour, bit 4 (speaker) clear
        out ($FE),a
q_next: ld hl,(qptr)
        ld a,(hl)
        inc hl
        ld (qptr),hl
        cp $FF
        jp z,q_end
        cp 64
        jr nc,q_next
        add a,a
        ld e,a
        ld d,0
        ld hl,allotab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
f_next: ld a,(hl)               ; frame header: 0 end, $80+n n silent frames,
        inc hl                  ; else n = repeats of the 37-byte frame that follows
        or a
        jr z,q_next
        jp m,f_sil
        ld c,a
        push hl
        pop ix
f_rep:  ld d,37
bloop:  ld e,(hl)
        inc hl
;@BITS
        dec c
        jp z,f_next             ; HL is now past the frame
        push ix
        pop hl
        jr f_rep
f_sil:  and $7F
        ld c,a
s_frm:  ld de,1381              ; 1381 x 24 T ~ one frame (296 x 112 T); jp nz is 10 T
s_lp:   dec de
        ld a,d
        or e
        jr nz,s_lp
        dec c
        jp nz,s_frm
        jp f_next
q_end:  ld a,b
        out ($FE),a
        ei
        ret

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
        jr z,cv_ne
        cp 13
        jr z,cv_ne
        call mapch
        cp ' '
        jr nz,cv_put
        dec de
        ld a,(de)
        inc de
        cp ' '
        jr z,cv_skip            ; runs of spaces become one
        ld a,' '
cv_put: ld (de),a
        inc de
cv_skip: djnz cv_nl
cv_ne:  dec de
        ld a,(de)
        inc de
        cp ' '
        jr z,cv_e2
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
        jr c,c_skip
        cp 64
        jr nc,c_skip
        add a,a
        ld e,a
        ld d,0
        ld ix,gindex
        add ix,de
        ld e,(ix+0)
        ld d,(ix+1)
        ld a,d
        or e
        jr z,c_skip
        push de
        pop ix                  ; IX = first rule of the group
r_try:  ld a,(ix+0)
        cp $FF
        jr z,c_skip             ; no rule: skip the character
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
        jr z,r_mok
r_m:    ld a,(de)
        and $7F
        cp (hl)
        jr nz,r_try
        inc hl
        ld a,(de)
        inc de
        rla
        jr nc,r_m
r_mok:  ld (rpos),hl            ; just past the match
        ; left context, leftwards from cur-1
        ld hl,(cur)
        dec hl
        ld de,(lptr)
        call ctx_left
        jr nz,r_try
        ; right context
        ld hl,(rpos)
        ld de,(rptr)
        call ctx_right
        jr nz,r_try
        ; matched: emit
        ld hl,(optr)
        ld a,(hl)
        cp $80
        jr z,r_emitd
r_e:    ld a,(hl)
        and $7F
        call emit
        ld a,(hl)
        inc hl
        rla
        jr nc,r_e
r_emitd: ld hl,(rpos)
        jp c_loop
c_skip: ld hl,(cur)
        inc hl
        jp c_loop
c_done: ld hl,(outp)
        ld (hl),$FF
        ld de,allbuf
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ret

; emit A: pauses (0-4) at the start are dropped, a pause after a pause keeps the longer
emit:   push hl
        ld hl,(outp)
        cp 5
        jr nc,em_put
        ld de,allbuf
        push hl
        or a
        sbc hl,de
        pop hl
        jr z,em_x               ; nothing yet: drop a leading pause
        dec hl
        ld c,a
        ld a,(hl)
        cp 5
        jr nc,em_p2
        cp c                    ; previous is a pause: keep the longer
        jr nc,em_x
        ld (hl),c
        jr em_x
em_p2:  inc hl
        ld a,c
em_put: ld de,allbuf+510
        ex de,hl
        or a
        sbc hl,de
        ex de,hl
        jr c,em_x               ; full
        ld (hl),a
        inc hl
        ld (outp),hl
em_x:   pop hl
        ret

; mapch: A -> A-Z, 0-9, , . ? - ' or a space (as tools/front.py normalise)
mapch:  cp 'a'
        jr c,mc_1
        cp 'z'+1
        jr nc,mc_sp
        sub 32
        ret
mc_1:   cp 'A'
        jr c,mc_2
        cp 'Z'+1
        ret c
        jr mc_sp
mc_2:   cp '0'
        jr c,mc_3
        cp '9'+1
        ret c
mc_3:   cp ','
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
        jr nc,nextpart
        ret

; letter flags of A: 1 vowel 2 consonant 4 voiced 8 front 16 sibilant 32 "@"; Z if not a letter
flagsof: sub 'A'
        jr c,fo_no
        cp 26
        jr nc,fo_no
        push hl
        ld hl,lflags
        add a,l
        ld l,a
        jr nc,fo_1
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
        jr nc,cl_el
        xor a
        ret
left1:  ld a,c
        cp 10
        jr c,l_cls
        cp (hl)                 ; a literal
        ret nz
        dec hl
        ret
l_cls:  cp 9
        jr z,l_space
        cp 1
        jr z,l_vow
        cp 2
        jr z,l_colon
        cp 3
        ld c,2
        jr z,l_one
        cp 4
        ld c,4
        jr z,l_one
        cp 5
        ld c,8
        jr z,l_one
        cp 7
        jr z,l_amp
        cp 8
        jr z,l_at
        or a                    ; % (not used on the left): fail
        ret
l_space: ld a,(hl)
        call flagsof
        jr nz,l_fail
        dec hl
        xor a
        ret
l_vow:  ld a,(hl)
        call flagsof
        and 1
        jr z,l_fail
lv_1:   dec hl
        ld a,(hl)
        call flagsof
        and 1
        jr nz,lv_1
        xor a
        ret
l_colon: ld a,(hl)
        call flagsof
        and 2
        jr z,l_ok
        dec hl
        jr l_colon
l_one:  ld a,(hl)
        call flagsof
        and c
        jr z,l_fail
        dec hl
l_ok:   xor a
        ret
l_fail: or 1
        ret
l_amp:  ld c,16
        ld b,'C'
        ld a,'S'
        jr l_two
l_at:   ld c,32
        ld b,'T'
        ld a,'C'
l_two:  ld (two_a),a
        ld a,(hl)
        call flagsof
        and c
        jr nz,l_one1
        ld a,(hl)
        cp 'H'
        jr nz,l_fail
        dec hl
        ld a,(hl)
        cp b
        jr z,l_two2
        cp 'S'
        jr z,l_two2
        push hl
        ld hl,two_a
        cp (hl)
        pop hl
        jr nz,l_fail2
l_two2: dec hl
        xor a
        ret
l_fail2: inc hl
        jr l_fail
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
        jr nc,cr_el
        xor a
        ret
rinc:   ld a,(hl)               ; step right, but never past the end
        or a
        ret z
        inc hl
        ret
right1: ld a,c
        cp 10
        jr c,r_cls
        cp (hl)
        ret nz
        inc hl
        xor a
        ret
r_cls:  cp 9
        jr z,r_space
        cp 1
        jr z,r_vow
        cp 2
        jr z,r_colon
        cp 3
        ld c,2
        jr z,r_one
        cp 4
        ld c,4
        jr z,r_one
        cp 5
        ld c,8
        jr z,r_one
        cp 6
        jr z,r_pct
        cp 7
        ld c,16
        jr z,r_two
        ld c,32                 ; 8: @
        jr r_two
r_space: ld a,(hl)
        call flagsof
        jr nz,r_fail
        call rinc
        xor a
        ret
r_vow:  ld a,(hl)
        call flagsof
        and 1
        jr z,r_fail
rv_1:   inc hl
        ld a,(hl)
        call flagsof
        and 1
        jr nz,rv_1
        xor a
        ret
r_colon: ld a,(hl)
        call flagsof
        and 2
        jr z,r_ok
        inc hl
        jr r_colon
r_one:  ld a,(hl)
        call flagsof
        and c
        jr z,r_fail
        inc hl
r_ok:   xor a
        ret
r_fail: or 1
        ret
r_two:  inc hl                  ; CH or SH (and TH for @) count as one
        ld a,(hl)
        dec hl
        cp 'H'
        jr nz,r_two1
        ld a,(hl)
        cp 'C'
        jr z,r_two2
        cp 'S'
        jr z,r_two2
        cp 'T'
        jr nz,r_two1
        ld a,c
        cp 32
        jr nz,r_two1
r_two2: inc hl
        inc hl
        xor a
        ret
r_two1: ld a,(hl)
        call flagsof
        and c
        jr z,r_fail
        inc hl
        xor a
        ret
r_pct:  push de                 ; % : ING, ELY, ER, ES, ED or E
        ld de,sfx
rp_1:   ld a,(de)
        or a
        jr z,rp_no
        push hl
rp_2:   ld a,(de)
        and $7F
        cp (hl)
        jr nz,rp_nx
        inc hl
        ld a,(de)
        inc de
        rla
        jr nc,rp_2
        pop af                  ; drop the saved text pointer
        pop de
        xor a
        ret
rp_nx:  pop hl
rp_3:   ld a,(de)
        inc de
        rla
        jr nc,rp_3
        jr rp_1
rp_no:  pop de
        jr r_fail
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
;@TABLES
codeend:
textbuf equ codeend             ; 256 bytes: BASIC POKEs the text here
wbuf0   equ textbuf+256
wbuf    equ wbuf0+4             ; 260: the normalised text
allbuf  equ wbuf+260            ; 512: allophone codes
bufend  equ allbuf+512
