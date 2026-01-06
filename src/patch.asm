include 'inc/ez80.inc'
include 'inc/tiformat.inc'
include 'inc/ti84pceg.inc'

name := 'UPDATE'
header := 'UPD'
version := '1.0'

format ti archived executable appvar name

swap_size := $10000
substitutions_size := $FF

virtual at ti.pixelShadow
	ram_store::
	ram_code_area rb lengthof ram_code
	privileged_sector rb 1
	curr_addr rb 3
	curr_block := $-1
	temp_block rb 3
	boot_subs_removed rb 1
	swap_mem rb swap_size
	substitutions rb substitutions_size
end virtual

virtual at 0 as 'bin'
	db header
	db version
	db xip_code
	load data: $ - $$ from $$
end virtual

db data

virtual at entry_data
	raw::
end virtual

macro entries
	local curr_entry, curr_offset
	curr_entry = 0
	curr_offset = 0
	macro entry
		local replacement_count
		replacement_count = 0
		macro replace index, args&
			local seq, sub1, sub2, is_call
			is_call = 0
			match [a] [b] [c], args
				define seq a
				define sub1 b
				define sub2 c
			else match [a] [b], args
				define seq a
				define sub1 b
			else match [a] <b>, args
				define seq a
				define sub1 b
				is_call = 1
			else
				err 'invalid args'
			end match

			virtual raw
				repeat 1, i:curr_entry
					entry_#i:
				end repeat
				.seq_size db 0
				match -, seq
				else
					db seq
				end match
				store $ - .seq_size - 1: 1 at .seq_size
				.replace_size db 0
				if defined sub2
					db 0
				else
					db 1
				end if
				db index
				.substitution1:
				if is_call
					db $CD
					emit 3: sub1
				else
					db sub1
				end if
				store $ - .substitution1 at .replace_size
				if defined sub2
					db sub2
				end if
			end virtual

			replacement_count = replacement_count + 1
			curr_entry = curr_entry + 1
		end macro

		macro from type, addr*, patches&
			match =jump?, type
				db 0
			else match=absolute?, type
				db 1
			else
				err 'invalid source type'
			end match
			emit 3: addr
			db replacement_count
			repeat replacement_count, i:curr_offset
				emit 3: entry_#i
			end repeat
		end macro
		macro end?.entry
			curr_offset = curr_offset + replacement_count
			replacement_count = 0
		end macro
	end macro

	macro end?.entries
		db 2
		virtual raw
			load raw_data: $ - $$ from $$
		end virtual
		entry_data db raw_data
	end macro
end macro

virtual at ram_code_area
ram_code_start:
patches_start:
entries
	entry
		; expand flash memory mapping mask
		replace 2, [$21, $00, $C0, $FF] [$80] [$40]
		; expand boot code erase flash region
		replace 1, [$06, $3E] [$80] [$C0]
		from jump, $00004
	end entry
	entry
		; allow writing/erasing to expanded blocks
		replace 1, [$FE, $40] [$80] [$C0]
		from jump, ti.WriteFlash
		from jump, ti.EraseFlash
	end entry
	entry
		; don't mark blocks after 3A as garbage
		replace 1, [$3E, $3A] [$7F] [$BF]
		from absolute, $023000
	end entry
	entry
		; constants used to calculate archive size
		replace 3, [$21, $FD, $FF, $3A] [$7F] [$BF]
		replace 3, [$21, $FD, $FF, $3A] [$7F] [$BF]
		; relocate the top of the app region
		replace -4, [$7E, $FE, $FF] [$21, $00, $00, $40]
		from jump, $021EDC
	end entry
	entry
		; constant used to calculate archive size
		replace 3, [$21, $FD, $FF, $3A] [$7F] [$BF]
		from absolute, $005000
	end entry
	entry
		; constant used to calculate archive size
		replace 3, [$21, $FF, $FF, $3A] [$7F] [$BF]
		from absolute, $040000
		; another copy was in introduced here in TI-OS 5.8.3 (hmmmm...)
		from absolute, $080000
		; located here on TI-OS <5.7
		from absolute, $0B0000
	end entry
	entry
		; constants used by the DUSB protocol to calculate the size of flash/archive
		replace 0, [$40, $ED, $43, $1A] [$80] [$C0]
		replace 0, [$36, $ED, $43, $1A] [$76] [$B6]
		; the boot code has a separate copy of this code which is conveniently located in a jump table routine
		from jump, $00043C
		from absolute, $040000
		; located here on TI-OS <5.7
		from absolute, $080000
		from absolute, $090000
	end entry

	; routine trampolining

	; erase the expanded sectors when clearing archive from the OS
	entry
		replace 0, [$FE, $3B, $30] [$FE] [$FE] ; first match
		replace 0, [$FD, $CB] <EraseArchive_patch>
		from absolute, $025000
	end entry
	; move the bottom of the app region
	entry
		replace 2, [-] <LoadDEIndFlash_patch>
		from jump, ti.LoadDEIndFlash
	end entry
	; make ArcChk skip sectors 3B-3F when calculating size
	entry
		replace 0, [$21, $00, $00, $00] <ArcChk_patch>
		from jump, ti.ArcChk
	end entry
	; make NextFlashPage jump over sectors 3B-3F
	entry
		replace 0, [$FE, $3B] <NextFlashPage_patch>
		from jump, ti.NextFlashPage
	end entry
	; make PrevFlashPage jump over sectors 3B-3F
	entry
		replace 0, [$BB, $28, $01] <PrevFlashPage_patch>
		from jump, ti.PrevFlashPage
	end entry
	; if the input is larger than 9999K, change units and continue
	entry
		replace 0, [$11, $00, $00, $00] <Draw32_patch>
		replace 0, [$21, $0E, $06, $D0] <Draw32_patch2>
		from jump, ti.Draw32
	end entry

	;;
	entry
		replace 0, [-] <os_install_hook>
		from jump, ti.MarkOSValid
	end entry
	;;

	; not related to the patch. signature check disabling related stuff.
	entry
		replace 0, [-] [$C9]
		from jump, ti.FindAppHeaderSubField
	end entry
	entry
		replace 3, [$B0, $28, $06] [$00, $00, $00, $00]
		from absolute, $006000
	end entry
end entries
patches_end:

check_os:
	ld hl, ($020100)
	ld bc, $A55A
	or a
	sbc.sil hl, bc
	ld hl, ($02001A) ; os version
	ret

is_patched:
	ld a, (patched_size)
	cp a, $FF
	ret

determine_patch_size:
	call is_patched
	jr nz, .compare
	call flash_size
.compare:
	cp a, $C0
	jr nz, .next
	ld a, 1
	ret
.next:
	ld a, 0
	ret

patch_boot:
	push af
	set 1, a
	call apply_patches
	bit 0, a
	jr nz, .next
	ld a, $80
	jr .set
.next:
	ld a, $C0
.set:
	ld hl, .data+2
	ld (hl), a
	dec hl
	dec hl
	ld de, patched_size
	ld bc, 3
	call flash_write
	ld hl, substitutions
	ld de, patch_map
	ld bc, substitutions_size
	call flash_write
	pop af
	ret
.data rb 3

calculate_checksum:
	ld b, substitutions_size - 1
	xor a
.add:
	ld c, (hl)
	inc hl
	add a, c
	djnz .add
	ret

get_os_substitutions_raw:
	ld de, $4200
	jp ti.FindFirstCertField

get_os_substitutions:
	call get_os_substitutions_raw
	ret nz
	inc hl
	inc hl
	inc hl
	push hl
	call calculate_checksum
	ld b, a
	ld a, (hl)
	cp a, b
	pop hl
	ret

remove_os_substitutions:
	call get_os_substitutions_raw
	ret nz
	ld bc, 1
	ld (hl), b
	ex de, hl
	ld hl, $E40000 ; fetch a 0
	call flash_write
	jp ti.CleanupCertificate

patch_os_skip_check:
	push af
	jr patch_os.start

patch_os:
	push af
	call check_os
	jr nz, .end
.start:
	call remove_os_substitutions
	pop af
	push af
	res 1, a
	call apply_patches
	call ti.GetCertificateEnd
	ex de, hl
	ld hl, .header
	ld bc, 3
	call flash_write
	ld hl, substitutions
	push hl
	push de
	call calculate_checksum
	ld (hl), a
	pop de
	pop hl
	ld bc, substitutions_size
	call flash_write
.end:
	pop af
	ret	
.header db $42, $0D, substitutions_size ; cert field with id 420

unpatch_boot_callback:
	dec a
	jr nz, .call
	; remove the header from storage
	header_in_swap = swap_mem + (header_start and $FFFF)
	ld hl, header_in_swap
	ld (hl), $FF
	ld de, header_in_swap + 1
	ld bc, (storage_start - header_start) - 1
	ldir
	inc a
	ld (boot_subs_removed), a
.call:
	call 0
.callback := $-3
	ret

unpatch_boot:
	xor a
	ld (boot_subs_removed), a
	ld hl, (write_swap_to_flash.callback)
	push hl
	ld (unpatch_boot_callback.callback), hl
	ld de, unpatch_boot_callback
	ld (write_swap_to_flash.callback), de
	ld hl, patch_map
	call remove_patches
	pop hl
	ld (write_swap_to_flash.callback), hl
	ld a, (boot_subs_removed)
	or a
	ret nz
	; if sector 01 is never patched:
	ld hl, storage_start
	ld bc, lengthof xip_code
	jp update_patch_code

unpatch_os:
	call check_os
	ret nz
	call get_os_substitutions
	ret nz
	call remove_patches
	jp remove_os_substitutions

update_patch_code:
	ld hl, $010000
	call write_swap
	jp write_swap_to_flash

remove_patches:
	ld a, (hl)
	inc hl
	cp a, $FF
	ret z
	push hl
	ld (curr_block), a
	ld hl, (curr_addr)
	call write_swap
	pop hl
.next:
	ld de, (hl)
	ld c, 3
	add hl, bc
	ld c, (hl)
	inc hl
	inc c
	jr z, .next_block
	dec c
	ldir
	jr .next
.next_block:
	push hl
	call write_swap_to_flash
	pop hl
	jr remove_patches

apply_patches:
	push af
	ld a, $FF
	ld (curr_block), a
	ld iy, substitutions
.loop:
	pop af
	push af
	ld ix, patches_start
	call patch_block
	ld a, (curr_block)
	call write_swap_to_flash
	ld de, $FFFFFF
	ld (iy), de
	ld (iy+3), d
	lea iy, iy+4
	jr nz, .loop
.end:
	ld a, $FF
	ld (iy), a
	pop af
	ret

write_swap_to_flash:
	ld a, (curr_block)
	cp a, $FF
	ret z
	push af, hl, de, bc
	call 0
.callback := $-3
	pop bc, de, hl, af
	call flash_erase
	ld hl, swap_mem
	ld de, (curr_addr)
	ld bc, $10000
	call flash_write
	ld a, $FF
	ld (curr_block), a
	ret

write_swap:
	ld de, swap_mem
	ld bc, swap_size
	ldir
	ret

patch_block:
	ld e, (ix) ; get location type (1 = jump, 0 = absolute)
	dec e
	jr z, .not_ended
	ret p
.not_ended:
	ld hl, (ix+1) ; get location address
	ld bc, 0
	or a
	sbc hl, bc ; check if the location is zeroed
	ld b, (ix+4) ; get number of sequences to match for the location
	lea ix, ix+5
	jr z, .skip ; if the location is zeroed, skip
	inc e
	jr nz, .start
	inc hl
	ld hl, (hl)
.start:
	ld (temp_block), hl
	ld de, (temp_block+2)
	bit 1, a ; should patch boot sectors bit
	push af
	jr nz, .is_boot
	ld a, $38 ; jr c
	jr .compare
.is_boot:
	ld a, $30 ; jr nc
.compare:
	ld (.jr_cond), a
	ld a, e
	cp a, $02
	jr c, .end_curr_block
.jr_cond := $-2
	; check current block
	ld a, (curr_block)
	cp a, $FF
	jr z, .loop_start ; we are not currently patching a block
	; check if we are currently patching the specified block
	cp a, e
	jr z, .loop_continue
.end_curr_block:
	pop af
.skip:
	ld c, 3
	mlt bc
	add ix, bc
	jr patch_block
.loop_start:
	; initial copy into swap mem
	push bc
	push hl
	ld h, 0
	ld l, 0
	call write_swap
	pop hl
	pop bc
.loop_continue:
	pop af
	; make search address relative to swap mem (swap_mem + 00XXXX)
	push bc
	ld b, h
	ld c, l
	ld hl, swap_mem
	add hl, bc
	; mark location as processed
	ld de, 0
	ld (ix-4), de
	; calculate first search size ($10000 - start of search)
	push hl
	ld hl, $10000
	sbc hl, bc
	push hl
	pop bc
	pop hl
.loop:
	; get the sequence to match against
	ld de, (ix)
	push af
	call find
	jr z, .found
	pop af
	pop bc
	jr .skip
.found:
	pop af
	push bc
	push af
	ld a, (curr_block)
	cp a, $FF
	jr nz, .calculate_offsets
	; block begin
	ld a, (temp_block+2)
	ld (curr_block), a
	ld (iy), a
	inc iy
.calculate_offsets:
	ex de, hl
	; jump over the sequence data
	ld bc, 0
	ld c, (hl)
	add hl, bc
	pop bc ; put configuration byte into b
	push bc
	inc hl
	ld c, (hl) ; replacement size
	inc hl
	ld a, (hl) ; two possible replacements?
	inc hl
	dec a
	ld a, (hl) ; replacement index
	jr z, .replace
	bit 0, b
	jr z, .replace
	ld b, 0
	add hl, bc ; go to the second replacement
.replace:
	; apply offset
	inc hl
	push bc
	push hl
	rla
	sbc hl, hl
	rra
	ld l, a
	push hl
	pop bc
	pop hl
	ex de, hl
	add hl, bc
	ex de, hl
	pop bc
	ld a, b
	ld b, 0
	; save the original value before modifiying
	ld (iy), de
	lea iy, iy+3
	ld (iy), c
	inc iy
	push hl
	push de
	push bc
	ex de, hl
	lea de, iy
	ldir
	pop bc 
	add iy, bc
	pop de
	pop hl
	; write the value
	ldir
	inc a
.next:
	pop af
	pop bc
	ex hl, de
	lea ix, ix+3 ; go to next sequence
	ex (sp), hl
	dec h
	ex (sp), hl
	jp nz, .loop
	pop bc
	jp patch_block

find:
	; input:
	; hl = input data
	; bc = input data size
	; de = sequence
	; output:
	; on match:
	; hl = start of the match or end of input
	; de = sequence
	; z is set if found, reset if not
	ld a, (de)
	or a
	ret z
.start:
	inc de
	ld a, (de)
	cpir
	ret po
.compare_next:
	dec de
	push de
	ld a, (de)
	inc de
	push hl
	push bc
.loop:
	dec a
	jr z, .done
	push af
	inc de
	ld a, (de)
	cpi
	jr nz, .no_match
	pop af
	jr .loop
.no_match:
	jp po, .input_ended
	pop af
	pop bc
	pop hl
	pop de
	jr .start
.input_ended:
	pop af
.done:
	pop bc
	inc bc
	pop hl
	dec hl
	pop de
	ret

include 'flash.asm'
load ram_code: $ - $$ from $$
end virtual

virtual at $020000 - (lengthof xip_code + (storage_start - header_start))
header_start:
patch_map rb substitutions_size
patched_size rb 3

storage_start:
ram_code_storage db ram_code

recreate_patch_table:
	ld bc, patches_end - patches_start

copy_to_ram:
	ld hl, ram_code_storage
	ld de, ram_code_area
	ldir
	ret

init_patch_code:
	; make the universe privileged
	in0 a, ($1F)
	ld (privileged_sector), a
	; (the flash OS routines don't like when 1F is equal to FF. the only one we use is CleanupCertificate)
	ld a, $FE
	out0 ($1F), a

	; make patch code privileged
	; ld a, ram_code_area shr 16

	; ld de, ram_code_area + (lengthof ram_code) + 1
	; out0 ($25), a
	; out0 ($24), d
	; out0 ($23), e

	; ld de, ram_code_area
	; out0 ($22), a
	; out0 ($21), d
	; out0 ($20), e

	; copy patch code
	ld bc, lengthof ram_code
	call copy_to_ram

	ld a, $FF
	ld (curr_block), a

	; enable flash unlock sequence
	in0 a, ($06)
	set 2, a
	out0 ($06), a

	ld a, 4
	; flash unlock sequence
	di
	jr $+2
	di
	rsmix
	im 1
	out0 ($28), a
	in0 a, ($28)
	bit 2, a
	ret

clear_patch_code:
	; ; reset upper byte of privileged memory for the OS
	; ld a, $D1
	; out0 ($25), a
	; out0 ($22), a
	ld a, (privileged_sector)
	out0 ($1F), a
	; zero out region used by patch code
	ld hl, $E40000
	ld de, ram_code_area
	ld bc, sizeof ram_store
	ldir
	ret

boot_code_hook:
	call init_patch_code
	call ti.KeypadScan
	push hl, bc, de, af
	cp a, $05
	jr nz, .exit
	ld a, l
	cp a, $80
	jp z, access_patch_manager
.exit:
	if LOCK_BOOT = 1
	; ONLY THE PATCH MANAGER SHALL TOUCH THE BOOT SECTORS!
	call flash_temp_lock_boot_sectors
	end if
	call clear_patch_code
	pop af, de, bc, hl
	ret

os_install_patch_progress:
	ld hl, $1004
	jp ti.PutSpinner

os_install_hook:
	ld hl, $FFFFFF
	push hl, de, bc, ix, iy, af
	call init_patch_code
	ld hl, os_install_patch_progress
	ld (write_swap_to_flash.callback), hl
	ld a, 1
	ld (ti.curCol), a
	ld hl, .status
	call ti.boot.PutS
	ld hl, $0607
	ld (ti.curRow), hl
	ld hl, .details
	call ti.boot.PutS	
	call determine_patch_size
	call patch_os_skip_check
	call clear_patch_code
	pop af, iy, ix, bc, de, hl
	ret
.status: db 'Patching OS...    ', 0
.details: db 'patching is  ', 0

NextFlashPage_patch:
	cp a, $3B
	jr nz, .next
	; skip to the expanded archive sectors
	add a, 5
.next:
	cp a, $80
	jr nz, .end
	dec a
.end:
	inc a
	ret

PrevFlashPage_patch:
	cp a, e
	ret z
	cp a, $40
	jr nz, .end
	sub a, 5
.end:
	dec a
	ret

ArcChk_patch:
	ld hl, 0
	repeat 5
	dec b
	end repeat
	ret

LoadDEIndFlash_patch:
	push af
	push bc
	push hl
	ld bc, $3B0000
	or a
	sbc hl, bc
	jr nz, .end
	ld hl, (patched_size)
	ld h, 0
	ld l, 0
	ex (sp), hl
	ld a, 6
.loop:
	or a
	ld hl, (ix)
	sbc hl, bc
	jr nz, .next
	pop hl
	push hl
	ld (ix), hl
.next:
	lea ix, ix-3
	cp a, 3
	jr nz, .cont
	ld ix, 0
	add ix, sp
	; skip over the first 6 stack entries
	lea ix, ix+6*3
.cont:
	dec a
	jr nz, .loop
.end:
	ld ix, 0
	pop hl
	pop bc
	pop af
	ret

EraseArchive_patch:
	push af, bc, de
	ld a, $40
	ld bc, (patched_size+2)
.loop:
	push af
	call ti.EraseFlashSector
	pop af
	inc a
	cp a, c
	jr nz, .loop
	res 2, (iy+$25)
	pop de, bc, af
	ret

Draw32_patch:
	cp a, 7
	jr nz, .exit
	ld de, (ti.OP1-1) ; get input
	ld a, (ti.OP1+2)
	ld d, a
	ld a, (ti.OP1+3)
	ld e, a
	push hl
	; check if input will overflow
	ld hl, 10000000
	sbc hl, de
	pop hl
	ld a, 7
	jr z, .set
	jp p, .exit
.set:
	inc a
.exit:
	ld de, $000000
	ret

Draw32_patch2:
	ld a, c
	cp a, 8
	jr nz, .exit
	inc hl
	inc hl
	push de
	ld de, (hl)
	ld a, '.'
	ld (hl), a
	inc hl
	ld (hl), e
	inc hl
	ld (hl), d
	inc hl
	ld a, 'M'
	ld (hl), a
	inc hl
	xor a
	ld (hl), a
	pop de
.exit:
	ld hl, ti.OP3
	ret

include 'manager.asm'
jp boot_code_hook
load xip_code: $ - storage_start from storage_start
end virtual
