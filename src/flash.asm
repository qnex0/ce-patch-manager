; custom flash routines

flash_write_command_no_wait:
	ld de, $E00800
	ld bc, $10
	ldir
	ret

flash_command_wait:
	push hl
	ld hl, $E00824
.wait:
	bit 0, (hl)
	jr z, .wait
	set 0, (hl)
	pop hl
	ret

flash_write_command:
	call flash_write_command_no_wait
	jr flash_command_wait

flash_write_enable:
	ld hl, .cmd
	jr flash_write_command
.cmd:
	dd $00000000, $01000000, $00000000, $06000002

flash_erase:
	call flash_write_enable
	ld (.cmd+2), a
	ld hl, .cmd
	call flash_write_command
	jp flash_write_command
.cmd:
	dd $000000FF, $01000003, $00000000, $D8000002
	dd $00000000, $01000000, $00000000, $05000004

flash_write:
	push hl
	ld (.cmd), de
	; retrieve the bytes remaining in the starting page
	ld a, d
	and a, $0F
	ld d, a
	ld h, d
	ld l, 0
	inc h
	or a
	sbc.sis hl, de
	; check if input is smaller than the remaining page
	push hl
	or a
	sbc hl, bc
	pop hl
	jp m, .next
.smaller:
	ld h, b
	ld l, c
.next:
	ld.sis ((.cmd+8)-ti.ramStart), hl
	ld a, l
	; precalculate the next destination
	ex de, hl
	ld hl, (.cmd)
	add hl, de
	push hl
	push bc
	call flash_write_enable
	ld hl, .cmd
	call flash_write_command_no_wait
	pop bc
	pop hl
	ex (sp), hl
	ld de, $E00900
.write_flash:
	ldi
	dec de
	jp po, .end
	dec a
	jr nz, .write_flash
	pop de
	call flash_command_wait
	jr flash_write
.end:
	pop de
	jp flash_command_wait
.cmd:
	dd $00FFFFFF, $01000003, $0000FFFF, $32000042

flash_size:
	ld hl, .cmd
	call flash_write_command
	ld hl, $E00818
.wait:
	bit 1, (hl)
	jr z, .wait
	ld b, 3
.read:
	ld a, ($E00900)
	djnz .read
.end:
	sub a, $16
	ld bc, 0
	ld b, a
	ld c, 6
	mlt bc
	ld hl, .sizes
	add hl, bc
	push hl
	ld bc, 5
	add hl, bc
	ld a, (hl)
	pop hl
	ret
.sizes:
	db "4MB ", 	0, $40
	db "8MB ", 	0, $80
	db "16MB", 	0, $C0
	db "32MB", 	0, $C0
.cmd:
	dd $00000000, $01000000, $00000003, $9F000000

flash_temp_lock_boot_sectors:
	; the lock in question
	ret

flash_get_lock_status:
	ret