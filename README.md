# How to use

To install the patch manager, you must dump the ROM from your calculator and run the installer program, which will produce a patched ROM file which you can upload to your new flash chip. This process requires for the boot sectors to be unlocked. The only way to unlock them is if you replaced your flash chip and didn’t explicitly lock them afterwards. Press The installer will automatically determine the size of your flash chip and place the patch code in a boot sector. The patch will then be installed. After installation, you may access the patch menu by quick pressing the reset button while holding the alpha key. The patch menu allows you to unpatch at any time.

# Persistence
The patch code will automatically patch the OS during OS reinstalls/upgrades. It has been tested on OS versions 5.3-5.8 so the likelihood of the patches working on future untested OS versions is high. 

# Information
The patch code is designed for upgradeability in mind. If a new version of the installer is ran, the installer will automatically update the patch code and repatches. 

# How it works

This patcher modifies the:

- [Flash address mask](#flash-address-mask) to map the expanded flash area.
- Constants used to calculate the size of the archive.
- WriteFlash and EraseFlash routines to allow writing past sector 3F.
- [NextFlashPage](#nextflashpage--prevflashpage) and [PrevFlashPage](#nextflashpage--prevflashpage) routines to jump over [sectors 3B-3F](#sectors-3b-3f)
- [ArcChk](#arcchk) routine to not count [sectors 3B-3F](#sectors-3b-3f) towards the archive size.
- Code to make TI-OS not mark sectors in archive placed after 3A (end of original archive) as [garbage](#garbage) after a transfer finishes.
- Boot code / OS flash erase routines to erase the expanded sectors.
- The [LoadDEIndFlash](#loaddeindflash) routine to relocate the app region to the bottom of the extended flash.
- Relocated the top of the app region to the sector after 3F instead of the start of archive so apps can’t grow into [sectors 3B-3F](#sectors-3b-3f).


# Key

### Flash address mask

The CE ASIC supports mapping up to 12MB of flash. By default, only addresses 000000 to 3FFFFF are mapped (4MB). There is 8MB of unmapped memory 400000-CFFFFF right after, which ends before the start of RAM (D00000). The 32-bit flash address mask defines the amount of flash to map. By default, it is set to ~(FFC00000) = 3FFFFF. We can change this depending on the amount flash we want to map.

### Sectors 3B-3F

These sectors are not used for the archive and are placed at the end of the original 4MB flash.
- Sector 3B is reserved for holding the certificate, a region used to store data that should persist between OS installs (e.g serial numbers and minimum OS version).
- Sectors 3C-3F are used as a RAM backup in the OS during deep sleep mode.
- Sector 3F is also used as a swap sector when performing flash defragmentation.

These sectors are also read/written to from a few 3rd party programs such as [Cesium](https://github.com/mateoconlechuga/cesium/blob/master/src/flash.asm) and [Cermastr](https://tiplanet.org/forum/archives_voir.php?id=1581757), therefore, they will remain in sectors 3B-3F to maintain compatibility with these programs.

### Garbage

The second byte of every archive entry contains a status byte. It is initially set to FC and set to FE after the transfer successfully completes. If the status byte remains FC (due to an error during the transfer), it will be erased during the next garbage collect.

### ArcChk
ArcChk is a routine that is used to calculate the current size of the archive. Because we skipped [sectors 3B-3F](#sectors-3b-3f), we need to patch the routine to subtract 5 from the count of sectors there are

### NextFlashPage / PrevFlashPage
These routines are used by the archive code to increment / decrement the current flash sector. Conveniently, the archive is sector aligned, meaning that data in one sector can’t continue writing into the next sector. This means that we can simply modify these routines to jump over sectors without any issues.

### LoadDEIndFlash
by embedded a "preprocess" routine that scans the input/last few stack entries for 3B0000 (this makes 3rd party app installers still work without any modifications)made both the boot code/OS erase routines acknowledge the new sectorsmade the WriteFlash/EraseFlash routines allow sectors after 3f to be usedrelocated the top of the app region to 400000 instead of 0C0000 (so apps can’t grow into sectors 3b-3a, apps execute from flash and therefore are not sector aligned, so we can’t )

# Extra info
