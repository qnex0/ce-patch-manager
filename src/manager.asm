macro section name, func*
    db name, 0
    emit 3: func
end macro

virtual ram_store
	text_mem rb 36
	sections_cache rb 1
	text_fg rb 1
	text_bg rb 1
	ram_store_end:
end virtual

text_height := 18
text_width := 12
text_vert_step := 8

namespace color
	white 	:= 255
	black 	:= 0
	green 	:= 1
	red  	:= 2
	cyan  	:= 3
	orange 	:= 4
	finish	:= 5
end namespace

colors:
	dw $0000
	dw $0643
	dw $D800
	dw $069B
	dw $FA40

namespace strs
	title 			db 'Patch manager', 0
	controls 		db 'ENTER: Patch, MODE: Boot', 0
	version_num		db 'v', version, 0
	yes 			db 'Yes', 0
	no 				db 'No', 0
	namespace warnings
		reset 		db 'Long press Rst+Alpha', 0
	end namespace
	namespace file
		none 		db 'No file found', 0
		invalid		db 'Invalid format', 0
		found 		db 'Press 2nd', 0
	end namespace
	namespace flash_status
		unlocked 	db 'Unlocked', 0
		temp 		db 'Temp lock', 0
		otp 		db 'OTP lock', 0
	end namespace
	namespace patched
		yes 		db 'Patched', 0
		no 			db 'Not patched', 0
	end namespace
end namespace


layout:
    section 'Flash size',		layout_get_size
	section 'Status',			layout_get_status
	section 'Boot sectors',	 	layout_get_boot_sectors 
	section 'Update',			layout_check_update
	section 'OS installed', 	layout_check_os
    section '', 0

; boot_PutS was lacking features that I wanted so I made my own
; minimal text routine that uses the boot codes font.

disp_init:
	ld hl, colors
	ld de, ti.mpLcdPalette
	ld bc, color.finish*2
	ldir
	ld de, $FFFF
	ld (ti.mpLcdPalette+(2*$FF)), de
	ld a, $27
	ld (ti.mpLcdCtrl), a
	ld bc, $0102
	ret

disp_deinit:
	ld a, $2D
	ld (ti.mpLcdCtrl), a
	ret

disp_c:
    push bc
    ; retrieve font offset for char
	call ti.boot.GetLFontPtr
	ld d, a
	ld e, 28
	mlt de
	add hl, de
    ; copy char data into padded memory for the top and bottom lines
	push bc
	ld de, text_mem+4
	ld bc, 28
	ldir
	pop bc
	; calculate start point, b = x, c = y
	ld d, c
	ld e, text_vert_step
	mlt de
	ld c, e
	ld hl, ti.vRam
	ld de, 320
.y_pos:
	add hl, de
	dec c
	jr nz, .y_pos
.x_pos:
	ld d, b
	ld e, text_width
	mlt de
	add hl, de
.start:
	ex de, hl
	ld ix, text_mem
	ld c, text_height
.start_row:
	pea ix+2
	ld a, (ix+1)
	ld hl, 0
	ld l, a
	add hl, hl
	ld a, (ix)
	rra
	rra
	or a, h
	ld h, a
	ld b, text_width+2
.loop:
	bit 7, h
	add hl, hl
	jr z, .bg_bit
	ld a, (text_fg)
	jr .set
.bg_bit:
	ld a, (text_bg)
.set:
	ld (de), a
	inc de
	djnz .loop
.end_row:
	pop ix
	ld a, c
	ld bc, 320-(text_width+2)
	ex de, hl
	add hl, bc
	ex de, hl
	ld c, a
	dec c
	jr nz, .start_row
    pop bc
	ret

disp_s:
	ld a, (hl)
	or a
    ret z
	inc hl
	push hl
	call disp_c
	inc b
	pop hl
	jr disp_s

set_color:
	ld (text_bg), a
	cp a, $FF
	ld a, $FF
	jr nz, .end
.clear:
	inc a
.end:
	ld (text_fg), a
	ret

new_line:
	inc c
	inc c
	inc c
	ld b, 1
	ret

check_os:
	ld hl, ($020100)
	ld bc, $A55A
	or a
	sbc.sil hl, bc
	ld hl, ($02001A) ; os version
	ret

layout_check_os:
	call check_os
	jr nz, .not
	ld a, color.white
	ld hl, strs.yes
	jr .end
.not:
	ld a, color.red
	ld hl, strs.no
.end:
	ret

layout_get_size:
	call flash_size
	ld a, color.white
	ret

layout_get_status:
	ld a, color.green
	ld hl, strs.patched.yes
	ret

layout_get_boot_sectors:
	call flash_get_lock_status
	ld a, color.orange
	ld hl, strs.flash_status.temp
	ret

layout_check_update:
	call check_os
	jr nz, .not_found
	; manually load archive variables into symTable for ChkFindSym to work before boot
	ld hl, ti.symTable
	ld (ti.progPtr), hl
	ld (ti.pTemp), hl
	ld (ti.OPBase), hl
	ld (ti.OPS), hl
	; find load routine
	ld hl, $026000
	ld de, .load_routine
	ld bc, $20000
	call find
	jr nz, .not_found
	ld bc, 4
	sbc hl, bc
	ld bc, .search
	push bc
	jp (hl)
.search:
	ld hl, .file_name
	call ti.Mov9ToOP1
	call ti.ChkFindSym
	jr c, .not_found
	ex de, hl
	; skip VAT header and name
	ld bc, 9 + 11
	add hl, bc
	; check header
	ld de, .header
	ld bc, 3
	call find
	jr nz, .invalid

	; do stuff with hl
	ld a, color.cyan
	ld hl, strs.file.found
	ret
.invalid:
	ld a, color.red
	ld hl, strs.file.invalid
	ret
.not_found:
	ld a, color.white
	ld hl, strs.file.none
	ret
.load_routine:
	db 4, $FD, $CB, $26, $A6
.header:
	db lengthof header, header
.file_name:
	db ti.AppVarObj, name, 0

process_layout:
    ld hl, layout
	ld bc, $010A
	ld a, color.white
	call set_color
.loop:
    call disp_s
	inc hl
	push hl
	ld hl, .sep
	call disp_s
    pop hl
    push hl
    push bc
    ld bc, .ret
    push bc
    ld hl, (hl)
    jp (hl)
.ret:
    pop bc
	call set_color
	call disp_s
	ld a, color.white
	call set_color
	pop hl
    inc hl
    inc hl
    inc hl
    ld a, (hl)
    or a
    ret z
	call new_line
    jr .loop
.sep:
    db ': ', 0

set_status_text:
	; push bc
	; push hl
	; ld bc, $0600
	; call new_line
	; call new_line
	; dec c
	; call disp_s
	; pop hl
	; pop bc
	ret

delay_200ms:
	push bc
	ld b, 20
.delay:
	call ti.Delay10ms
	djnz .delay
	pop bc
	ret

blink_status_text:
	push bc
	ld bc, $0640
.blink:
	ld a, (text_bg)
	bit 0, b
	jr nz, .sub 
	add a, c
	jr .set
.sub:
	sub a, c
.set:
	ld (text_bg), a
	call set_status_text
	call delay_200ms
	djnz .blink
	pop bc
	ret

patch_block_callback:
	; a = curr sector
	ret

key_enter:
	ld hl, patch_block_callback
	ld (patch_block.callback), hl
	ld a, 0
	set 0, a ; select first replacement
	set 1, a ; patch boot sectors
	call apply_patches
	res 1, a ; patch OS sectors
	call apply_patches
	ret

key_2nd:
	ret

draw_header:
	ld a, color.black
	call set_color
	; draw title
	ld hl, strs.title
	call disp_s
	call new_line
	; draw version num
	ld a, color.white
    call set_color
	ld hl, strs.version_num
	call disp_s
	; draw line separator
	call new_line
	dec c
.draw_line:
    ld a, '-'
    call disp_c
    inc b
    ld a, 20
    cp b
	ret z
	jr .draw_line

access_patch_manager:
	call disp_init
	call draw_header
	; draw sections
    call process_layout
	call new_line
	inc c
	; draw controls
	ld hl, strs.controls
	ld a, color.black
	call set_color
	call disp_s

	; call process_layout
	; ld hl, strs.flash_status
	; call set_status_text
.wait:
	call ti.KeypadScan
	cp a, $06
	jr z, .next
	cp a, $01
	jr z, .enter
	jr .wait
.enter:
	ld a, l
	cp a, $01
	jr nz, .wait
	call key_enter
	jr .wait
.next:
	ld a, l
	cp a, $20
	jr nz, .exit
	call key_2nd
	jr .wait
.exit:
	cp a, $40
	jr nz, .wait
	call disp_deinit
	call ti.boot.ClearVRAM
	jp z, boot_code_hook.exit