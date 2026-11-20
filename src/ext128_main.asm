; =====================================================================
; OpticBASIC 128 extension ROM (prototype): SAY, for a 128K Spectrum with
; OpticOS in ROM slot 0 and this ROM in slot 1. OpticOS (branch
; opticos128-say) pages slot 1 when a statement starts with a name that is
; not a PROC (see OpticOS src/ext128.asm); this ROM answers at ext_back.
;   SAY "text" / SAY a$     speak a string expression
;   SAY PITCH n             voiced period, 37 = normal, 24-56 (smaller = higher)
;   SAY VOICE AY / BUZZER   choose the AY chip or the beeper (also SAY VOICE 1 / 0)
;   SAY TUNE n              n = 0 monotone, 1 intonation
;   SAY LOAD                load the next four CODE blocks "bank4" "bank6" "bank1"
;                           "bank3" from tape into those RAM banks (a BASIC OUT to
;                           $7FFD would page out OpticOS's machine stack at $C000+)
; Sound data: RAM banks 4 (beeper), 6, 1, 3 (AY), each with its SPKD header,
; loaded with SAY LOAD (OpticOS's LD-BYTES, on a private stack). Settings persist
; in bank 4 at $FFF0. Workspace: $BA00-$BF07, borrowed for each SAY from the
; free memory between the variables (VEND) and the string heap (HP), so no
; CLEAR is needed; "No room" if a program reaches into it.
; tools/gen.py makes src/ext128.asm from this and speech_main.asm.
; =====================================================================
CH_ADD  equ $5C5D
ERR_NR  equ $5C3A
ERR_SP  equ $5C3D
VEND    equ $5BD8
HP      equ $5BD4
EMSGN   equ $5D49
EMBUF   equ $5DD0
E_NODATA equ $16                ; "Speech data not loaded" (own message, via EMSGN)

WS      equ $BA00
TEXTPTR equ WS
LISTPTR equ WS+2
STOPPED equ WS+4
PITCH   equ WS+5
INTON   equ WS+6
VARIANTS equ WS+7
DEVICE  equ WS+8
BANKM   equ WS+9
savsp   equ WS+10
TRAMP   equ WS+16               ; RAM code: call ROM 0 (34 bytes)
TR_T    equ TRAMP+15             ; the CALL's operand
ESTUB   equ WS+52               ; RAM code: page ROM 0 and RET (into ERR_SP's handler)
WVARS   equ WS+64               ; the speech code's work variables
WSTK    equ $C000               ; private stack $BF08-$BFFF: OpticOS's machine stack is at
                                ; $C000+ in bank 0, so it is paged out with the sound banks
textbuf equ WS+256
wbuf0   equ textbuf+256
wbuf    equ wbuf0+4
allbuf  equ wbuf+260
bufend  equ allbuf+512
SETS    equ $FFF0               ; settings, in bank 4: "SK" pitch inton variants device

        org $0000               ; RST 0 while this ROM is paged: page OpticOS, boot
        di
        ld bc,$7FFD
        xor a
        ld de,$FFFF
        jp OS_boot-2
        org $0038               ; IM 1 while this ROM is paged (briefly): just return
        push af
        pop af
        ei
        ret
        org OS_boot-2
        out (c),a               ; -> OpticOS's boot, as from its RESET
        org OS_ext_back-2
        out (c),a               ; back to ROM 0: the next fetch is its ext_back
        jp ext_main             ; ext_back: OpticOS pages us in here

ext_main:
        ld hl,(CH_ADD)          ; $01 type hash length name
        inc hl
        inc hl
        inc hl
        ld de,n_say
        call namecmp
        jr z,em_say
not_ours: ld bc,$7FFD
        xor a
        scf                     ; not ours: OpticOS's "No such PROC or FN"
        jp OS_ext_back-2
em_say: ld hl,(VEND)            ; the workspace must be free memory
        ld de,WS
        scf
        sbc hl,de
        jp nc,no_room
        ld hl,(HP)
        ld de,WSTK
        or a
        sbc hl,de
        jp c,no_room
        ld hl,tr_code           ; RAM code, pointers, settings
        ld de,TRAMP
        ld bc,tr_end-tr_code
        ldir
        ld hl,textbuf
        ld (TEXTPTR),hl
        ld hl,allbuf
        ld (LISTPTR),hl
        ld a,$10
        ld (BANKM),a
        xor a
        ld (STOPPED),a
        ld (savsp),sp           ; the whole statement runs on the private stack
        ld sp,WSTK
        call far
        dw OS_id_skip           ; step over SAY
        ld hl,(CH_ADD)
        ld a,(hl)
        cp OS_T_LOAD
        jp z,em_load
        call get_sets
        ld hl,(CH_ADD)
        ld a,(hl)
        cp 1
        jr nz,em_text
        inc hl
        inc hl
        inc hl
        ld de,n_pitch
        call namecmp
        jr z,em_pitch
        ld de,n_voice
        call namecmp
        jr z,em_voice
        ld de,n_tune
        call namecmp
        jr z,em_tune
em_text: call far
        dw OS_ev_expr
        call far
        dw OS_ev_pop            ; HL = the value: 0 1 length address
        ld a,(hl)
        inc hl
        or a
        jr nz,em_type
        ld a,(hl)
        inc hl
        cp 1
        jr nz,em_type
        ld a,(hl)
        inc hl
        cp 251
        jr c,em_l
        ld a,250
em_l:   ld c,a
        ld b,0
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld de,textbuf
        ld a,c
        or a
        jr z,em_z
        ldir                    ; the string may be in bank 0 at $C000+: copy it now
em_z:   xor a
        ld (de),a
        call say_text
done:   ld sp,(savsp)
        ld bc,$7FFD
        xor a                   ; NC: the statement is done
        jp OS_ext_back-2
em_type: call far
        dw OS_err_type
em_pitch: call far
        dw OS_id_skip
        call far
        dw OS_ev_int            ; DE
        ld a,d
        or a
        jr nz,em_arg
        ld a,e
        cp 24
        jr c,em_arg
        cp 57
        jr nc,em_arg
        ld (PITCH),a
        jr put_sets
em_arg: call far
        dw OS_err_arg
em_tune: call far
        dw OS_id_skip
        call far
        dw OS_ev_int
        ld a,d
        or a
        jr nz,em_arg
        ld a,e
        cp 2
        jr nc,em_arg
        ld (INTON),a
        jr put_sets
em_voice: call far
        dw OS_id_skip
        ld hl,(CH_ADD)
        ld a,(hl)
        cp 1
        jr nz,ev_num
        inc hl
        inc hl
        inc hl
        ld c,1
        ld de,n_ay
        call namecmp
        jr z,ev_set
        dec c
        ld de,n_buzz
        call namecmp
        jp nz,em_syn
ev_set: push bc
        call far
        dw OS_id_skip
        pop bc
        ld a,c
        jr ev_st
ev_num: call far
        dw OS_ev_int
        ld a,d
        or a
        jr nz,em_arg
        ld a,e
        cp 2
        jr nc,em_arg
ev_st:  ld (DEVICE),a
put_sets: ld bc,$7FFD           ; settings -> bank 4
        ld a,$14
        out (c),a
        ld hl,PITCH
        ld de,SETS+2
        ld bc,4
        ldir
        ld bc,$7FFD
        ld a,$10
        out (c),a
        jp done
em_syn: call far
        dw OS_err_syn
no_room: call far
        dw OS_err_nomem

; get_sets: check the four banks' SPKD headers, then settings from bank 4
get_sets: ld hl,banks
gs_lp:  ld a,(hl)
        or a
        jr z,gs_ok
        inc hl
        push hl
        ld c,a
        or $10
        push bc
        ld bc,$7FFD
        out (c),a
        pop bc
        ld hl,$C000
        ld de,spkd
        ld b,4
gs_c:   ld a,(de)
        cp (hl)
        jr nz,gs_bp
        inc de
        inc hl
        djnz gs_c
        ld a,($C006)
        cp c
gs_bp:  pop hl
        jr nz,gs_bad
        jr gs_lp
gs_bad: ld a,($C000)            ; what is there instead (for the message)
        ld e,a
        ld bc,$7FFD
        ld a,$10
        out (c),a
        push de
        push hl
        ld hl,m_nodata          ; own error: "No speech data in bank N (xx)"
        ld de,EMBUF
        ld bc,m_nod_e-m_nodata
        ldir
        pop hl
        dec hl
        ld a,(hl)
        add a,'0'
        ld (EMBUF+m_nod_n-m_nodata),a
        pop de
        ld a,e
        rrca
        rrca
        rrca
        rrca
        call hexd
        ld (EMBUF+m_nod_n-m_nodata+4),a
        ld a,e
        call hexd
        ld (EMBUF+m_nod_n-m_nodata+5),a
        ld a,E_NODATA
        ld (EMSGN),a
        jr os_err2
; os_err: OpticOS error A (its own message), from anywhere in this ROM
os_err: ld (ERR_NR),a
        ld a,$FF
        ld (EMSGN),a
        ld a,(ERR_NR)
os_err2: ld (ERR_NR),a
        ld sp,(ERR_SP)
        ld bc,$7FFD
        xor a
        jp ESTUB                ; ROM 0, RAM bank 0, and RET into its error handler

; SAY LOAD: four CODE blocks named "bankN" -> RAM bank N at $C000
em_load: ld hl,(CH_ADD)
        inc hl
        ld (CH_ADD),hl
        ld b,4
el_lp:  push bc
        ld ix,textbuf           ; the 17-byte header
        ld de,17
        xor a
        scf
        call far
        dw OS_LD_BYTES
        jr nc,el_err
        ld a,(textbuf)
        cp 3
        jr nz,el_err
        ld a,(textbuf+5)        ; "bankN": N
        sub '0'
        cp 8
        jr nc,el_err
        or $10
        ld (BANKM),a            ; far calls keep this bank paged
        ld de,(textbuf+11)
        ld ix,$C000
        ld a,$FF
        scf
        call far
        dw OS_LD_BYTES
        push af
        ld a,$10
        ld (BANKM),a
        ld bc,$7FFD
        out (c),a
        pop af
        jr nc,el_err
        pop bc
        djnz el_lp
        jp done
el_err: ld a,$10
        ld (BANKM),a
        ld a,OS_ERR_TAPE
        jr os_err
gs_ok:  ld bc,$7FFD             ; bank 4: settings
        ld a,$14
        out (c),a
        ld hl,(SETS)
        ld de,'S'+256*'K'
        or a
        sbc hl,de
        jr z,gs_have
        ld (SETS),de
        ld hl,defaults
        ld de,SETS+2
        ld bc,4
        ldir
gs_have: ld hl,SETS+2
        ld de,PITCH
        ld bc,4
        ldir
        ld bc,$7FFD
        ld a,$10
        out (c),a
        ret

; namecmp: HL = identifier length byte, DE = length-prefixed lower-case name;
; Z if equal (HL, BC kept)
namecmp: push hl
        push bc
        ld a,(de)
        ld b,a
        inc b
nc_lp:  ld a,(de)
        cp (hl)
        jr nz,nc_x
        inc de
        inc hl
        djnz nc_lp
nc_x:   pop bc
        pop hl
        ret

; far: call an OpticOS (ROM 0) routine, address inline after the CALL
far:    ex (sp),hl
        push de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (TR_T),de
        pop de
        ex (sp),hl
        jp TRAMP
tr_code:                        ; copied to TRAMP (RAM): ROM 0 in, call, ROM 1 back
        push af
        push bc
        ld bc,$7FFD
        ld a,(BANKM)
        and $EF                 ; ROM 0, the same RAM bank
        out (c),a
        pop bc
        pop af
        call 0                  ; operand = TR_T
        push af
        push bc
        ld bc,$7FFD
        ld a,(BANKM)            ; ROM 1 again
        out (c),a
        pop bc
        pop af
        ret
        ds ESTUB-TRAMP-($-tr_code)
        out (c),a               ; ESTUB: ROM 0 in, RET into the error handler
        ret
tr_end:

banks:  db 4, 6, 1, 3, 0
spkd:   db "SPKD"
defaults: db 37, 1, 1, 1        ; pitch, intonation, variants, device (AY)
n_say:  db 3, "say"
n_pitch: db 5, "pitch"
n_voice: db 5, "voice"
n_tune: db 4, "tune"
n_ay:   db 2, "ay"
n_buzz: db 6, "buzzer"
m_nodata: db "No speech data in bank "
m_nod_n: db "? ($xx", ')'+128
m_nod_e:
hexd:   and 15
        add a,'0'
        cp '9'+1
        ret c
        add a,7
        ret
