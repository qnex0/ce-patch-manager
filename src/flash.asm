; custom flash routines

flash_write_command:
	ld de, $E00800
	ld bc, $10
	ldir
	; push hl
	; ld hl, $E00824
.wait:
	; bit 0, (hl)
	; jr z, .wait
	; set 0, (hl)
	; pop hl
	ret

flash_erase:
	ld (.cmd+18), a
	ld hl, .cmd
	ld a, 3
.write:
	call flash_write_command
	dec a
	jr nz, .write
.wait:
	ret
.cmd:
	dd $00000000, $01000000, $00000000, $06000002
	dd $000000FF, $01000003, $00000000, $D8000002
	dd $00000000, $01000000, $00000000, $05000004

flash_write:
	push de
	push hl
	push bc
	; check if input is larger than a page
	ld hl, $100
	or a
	sbc hl, bc
	ret pe
	jp m, .next
	ld (.cmd+24), bc
.next:
	ld (.cmd+16), de
	ld hl, .cmd
	ld a, 2
.write:
	call flash_write_command
	dec a
	jr nz, .write
	inc d ; reset z
	ld de, $E00900
	pop bc
	pop hl
.write_flash:
	jr z, .end
	inc a
	ldi
	dec de
	jp pe, .write_flash
.end:
	pop de
	ret nz
	; ret if bc = 0
	ld a, b
	or c
	ret z
	; go to next destination and restart
	inc d
	jr flash_write
.cmd:
	dd $00000000, $01000000, $00000000, $06000002
	dd $00FFFFFF, $01000003, $00000100, $32000042

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