macro section name, func*
    db name, 0
    emit 3: func
end macro

virtual ram_store
	text_mem rb 36
	sections_cache rb 1
	text_fg rb 1
	text_bg rb 1
	temp_str rb lengthof patch_text + 1
	update_timer rb 1
	update_start_addr rb 3
	update_sym_addr rb 3
	ram_store_end:
end virtual

text_height := 18
text_width := 12
text_vert_step := 8

disp_buff := ti.vRam
disp_width := 320
disp_height := 240
disp_size := disp_width*disp_height

namespace color
	white 	:= 255
	black 	:= 0
	green 	:= 1
	red  	:= 2
	blue  	:= 3
	orange 	:= 4
	gray 	:= 5
	count	:= 6
end namespace

colors:
	dw $0000
	dw $8260
	dw $7C00
	dw $001F
	dw $FE24
	dw $6318

patch_text := 'Writing (00)'
update_text := 'Done! 0'

namespace strs
	hex_table			db '0123456789AB'
	title 				db 'Patch manager', 0
	version_num			db 'v', version, 0
	controls_del		db 'DEL: Unpatch, ', 0
	controls_enter 		db 'ENTER: Patch, ', 0
	controls_mode 		db 'MODE: Boot', 0
	os_installed 		db 'Installed', 0
	os_error 			db 'Error: reinstall', 0
	os_not_installed 	db 'Not installed', 0
	update_not_found 	db 'No file found', 0 
	update_invalid 		db 'Invalid format', 0
	update_found 		db 'Press 2nd', 0
	update_finished		db update_text, 0
	flash_unlocked 		db 'Unlocked', 0
	flash_lock 			db 'Temp lock', 0
	status_patched		db 'Patched', 0
	status_not_patched 	db 'Not patched', 0
	status_progress 	db patch_text, 0
end namespace

namespace layout_bit
	size		:= 0
	status		:= 1
	boot		:= 2
	update		:= 3
	os			:= 4
	errs		:= 7
end namespace

layout:
    section 'Flash size',		layout_get_size
	section 'Status',			layout_get_status
	section 'Boot sectors',	 	layout_get_boot_sectors 
	section 'Update',			layout_check_update
	section 'OS', 				layout_check_os
    section '', 0

; boot_PutS was lacking features that I wanted so I made my own
; minimal text routine that uses the boot codes font.

disp_init:
	ld hl, colors
	ld de, ti.mpLcdPalette
	ld bc, color.count*2
	ldir
	ld de, $FFFF
	ld (ti.mpLcdPalette+(2*$FF)), de
	ld a, $27
	ld (ti.mpLcdCtrl), a
	ret

disp_clear:
	ld hl, disp_buff + disp_size
	ld de, disp_buff
	ld bc, disp_size
	ldir
	ret

disp_deinit:
	ld a, $2D
	ld (ti.mpLcdCtrl), a
	ret

disp_resolve_cords:
	ld d, c
	ld e, text_vert_step
	mlt de
	ld c, e
	ld hl, disp_buff
	ld de, disp_width
.y_pos:
	add hl, de
	dec c
	jr nz, .y_pos
.x_pos:
	ld d, b
	ld e, text_width
	mlt de
	add hl, de
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
	call disp_resolve_cords
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
	ld bc, disp_width-(text_width+2)
	ex de, hl
	add hl, bc
	ex de, hl
	ld c, a
	dec c
	jr nz, .start_row
    pop bc
	inc b
	ret

disp_s:
	ld a, (hl)
	or a
    ret z
	inc hl
	push hl
	call disp_c
	pop hl
	jr disp_s

disp_color:
	ld (text_bg), a
	cp a, $FF
	ld a, $FF
	jr nz, .end
.clear:
	inc a
.end:
	ld (text_fg), a
	ret

disp_line:
	inc c
	inc c
	inc c
	ld b, 1
	ret

disp_line_clear:
	push bc
	call disp_resolve_cords
	ex de, hl
	inc de
	inc de
	; get distance from edge
	ld a, $1A
	sub a, b
	ld b, a
	ld c, text_width
	mlt bc
	inc bc
	ld a, text_height
.draw_row:
	push de
	push bc
	ld hl, ti.vRam + 320*240 ; read FF
	dec bc
	ldir
	pop bc
	pop hl
	ld de, disp_width
	add hl, de
	ex hl, de
	dec a
	jr nz, .draw_row
	pop bc
	ret

next_str:
	ld a, (hl)
	or a
	inc hl
	ret z
	jr next_str

set_err:
	ld a, (sections_cache)
	set layout_bit.errs, a
	ld (sections_cache), a
	ret

get_err:
	ld a, (sections_cache)
	bit layout_bit.errs, a
	ret

layout_check_os:
	call check_os
	jr nz, .not
	call is_patched
	jr z, .yes
	call get_os_substitutions
	jr z, .yes
	call set_err
	ld a, color.red
	ld hl, strs.os_error
	jr .end
.yes:
	ld a, color.white
	ld hl, strs.os_installed
	jr .end
.not:
	ld a, color.white
	ld hl, strs.os_not_installed
.end:
	ret

layout_get_size:
	call flash_size
	cp a, $40
	jr nz, .end
	call set_err
.end:
	ld a, color.white
	ret

layout_get_boot_sectors:
	call flash_get_lock_status
	ld hl, strs.flash_unlocked
	jr nz, .locked
	ld a, color.green
	ret
.locked:
	ld hl, strs.flash_lock
	ld a, color.orange
	ret

layout_get_status:
	ld a, (curr_block)
	cp a, $FF
	jr z, .not_patching
	ld hl, strs.status_progress
	ld de, temp_str
	push de
	ld bc, lengthof patch_text + 1
	ldir
	dec de
	dec de
	dec de
	ld hl, strs.hex_table
	ld c, a
	add hl, bc
	ld a, (hl)
	ld (de), a
	pop hl
	ld a, color.blue
	ret
.not_patching:
	call is_patched
	jr nz, .patched
	ld a, color.red
	ld hl, strs.status_not_patched
	jr .end
.patched:
	ld a, color.green
	ld hl, strs.status_patched
.end:
	ret

layout_check_update:
	ld a, (update_timer)
	or a
	jr z, .check
	push af
	ld hl, strs.update_finished
	ld de, temp_str
	push de
	ld bc, lengthof update_text + 1
	ldir
	dec de
	dec de
	ld c, '0'
	add a, c
	ld (de), a
	pop hl
	pop af
	dec a
	ld (update_timer), a
	ld a, color.green
	ret
.check:
	call check_os
	jp nz, .not_found
	; manually load archive variables into symTable for ChkFindSym to work before boot
	; TODO: manually search the archive, this is really ugly. (would also be useful for the future multi-boot feature)
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
	ld hl, .name
	call ti.Mov9ToOP1
	call ti.ChkFindSym
	jr c, .not_found
	ld (update_start_addr), de
	ld (update_sym_addr), hl
	ex de, hl
	; VAT header
	inc hl
	; get appvar size
	ld bc, 0
	ld c, (hl)
	inc hl
	ld b, (hl)
	push bc
	; skip to header
	ld bc, 18
	add hl, bc
	; check header
	ld de, .header
	ld bc, 3
	call find
	jr nz, .invalid
	; we have the bin loaded to hl
	; skip past header + version
	ld c, 6
	add hl, bc
	ex (sp), hl
	ld bc, 23 ; subtract header size
	sbc hl, bc
	ex (sp), hl
	pop bc
	call set_update
	ld a, color.blue
	ld hl, strs.update_found
	ret
.invalid:
	ld a, color.red
	ld hl, strs.update_invalid
	ret
.not_found:
	ld a, color.white
	ld hl, strs.update_not_found
	ret
.name db ti.AppVarObj, name, 0
.header db lengthof header, header
.load_routine db 4, $FD, $CB, $26, $A6

process_layout:
    ld hl, layout
	ld bc, $010A
	ld a, color.white
	call disp_color
	ld d, 1
.loop:
	ld a, (sections_cache)
	cpl
	and a, d
	jr nz, .cont
	call next_str
	jr .next
.cont:
	ld a, (sections_cache)
	or a, d
	ld (sections_cache), a
	push de
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
	call disp_color
	call disp_s
	call disp_line_clear
	ld a, color.white
	call disp_color
	pop hl
	pop de
.next:
    inc hl
    inc hl
    inc hl
	rl d
    ld a, (hl)
    or a
    ret z
	call disp_line
    jr .loop
.sep:
    db ': ', 0

draw_header:
	ld a, color.black
	call disp_color
	; draw title
	ld hl, strs.title
	call disp_s
	call disp_line
	; draw version num
	ld a, color.white
    call disp_color
	ld hl, strs.version_num
	call disp_s
	; draw line separator
	call disp_line
	dec c
.draw_line:
    ld a, '-'
    call disp_c
    ld a, 20
    cp b
	ret z
	jr .draw_line

draw_manager:
	xor a
	ld (sections_cache), a
	ld bc, $0102
	call draw_header
	; draw sections
    call process_layout
	call disp_line
	inc c
	; draw controls
	ld a, color.black
	call disp_color
	call get_err
	jr nz, .disp
	call is_patched
	ld hl, strs.controls_enter
	jr z, .disp
	ld hl, strs.controls_del
.disp:
	call disp_s
	ld hl, strs.controls_mode
	call disp_s
	jp disp_line_clear
	; controls_enter

patch_block_callback:
	ld a, (sections_cache)
	res layout_bit.status, a
	ld (sections_cache), a
	call process_layout
	ret

key_enter:
	call get_err
	ret nz
	call patch
	jp draw_manager

key_del:
	call get_err
	ret nz
	call unpatch
	jp draw_manager

key_2nd:
	call get_err
	ret nz
	call has_update
	ret z
	call is_patched
	push af
	call apply_update
	call process_layout
	ld hl, (update_sym_addr)
	ld de, (update_start_addr)
	call ti.DelVarArc
.countdown:
	ld b, 3
	ld a, b
	ld (update_timer), a
.loop:
	ld a, (sections_cache)
	res layout_bit.update, a
	ld (sections_cache), a
	push bc
	call process_layout
	ld b, 100
.wait:
	call ti.Delay10ms
	djnz .wait
	pop bc
	djnz .loop
	call disp_clear
	pop af
	ld a, 1
	jr z, .end
	ld (patch_on_boot), a
.end:
	ld (boot_into_manager), a
	jp entry_point

access_patch_manager:
	call disp_init
	call draw_manager
	ld hl, patch_block_callback
	ld (write_swap_to_flash.callback), hl
	xor a
	ld (boot_into_manager), a
	ld a, (patch_on_boot)
	or a
	jr z, .wait
	call patch
	call draw_manager
.wait:
	call ti.KeypadScan
	cp a, $06
	jr z, .second
	cp a, $01
	jr z, .enter
	jr .wait
.enter:
	ld a, l
	cp a, $01
	jr nz, .wait
	call key_enter
	jr .wait
.second:
	ld a, l
	cp a, $20
	jr nz, .del
	call key_2nd
	jr .wait
.del:
	cp a, $80
	jr nz, .exit
	call key_del
	jr .wait
.exit:
	cp a, $40
	jr nz, .wait
	; call disp_deinit
	; call disp_clear
	jp 0