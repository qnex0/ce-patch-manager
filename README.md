# Intro
<img width="500" height="330" alt="image" src="https://github.com/user-attachments/assets/accb0d77-10de-448e-982b-51c8a3e38777" />


The patch manager is a simple pre-boot environment that provides a central interface for managing and persisting ROM patches on the eZ80 series of TI calculators (that use a serial flash chip). The manager can be accessed by holding the `Alpha` key during a reset. Although applicable for applying general purpose patches, it was designed to apply patches related to the expansion of the TI-OS archive after upgrading the flash chip. It can increase the size of the archive from the original (approx 3.5MB) up to 11.5MB.

# How to install
Installing the patch manager requires that you replace the flash chip of your calculator. It assumes that you have access to the proper tools to program the new chip. The initial install of the patch manager requires you to use an external programmer to flash a patched ROM in order to circumvent the flash write protections. After the initial install, see [upgrades](#upgrades).

To install the patch manager, you must retrieve a ROM dump of your calculator. You can do this directly from the calculator by running an assembly program to produce a rom dump (e.g the one from CEmu) or by physically dumping the memory using your flash programmer.

The ROM should be a total of 4MB in size when dumped. Grab the installer from the release page ([or build it yourself](#building)), then run the executable from a command line, passing the path of the ROM file as the input. A new file with a _PATCHED suffix will be created if successful. This is what you need to flash to the new flash chip.

# How to enter
By default, the patch manager takes extra precautions when dealing with boot sectors. It applies a temporary lock to them that can only be cleared by a power cycle. You must hold the reset button for 4+ seconds (ensure that you are not connected to a power source), then hold `Alpha` and press `On`. If you explicitly disabled boot sector locking when [building](#building) the patch manager you can simply hold `Alpha` and short press the reset button.

# Persistence
<img width="405" height="397" alt="image" src="https://github.com/user-attachments/assets/3fe1030a-383e-469e-b1ba-4325b6deaf8e" />

The patch manager installs a hook that is invoked every time an OS is installed where it then runs the patching routine. This ensures that the OS is always patched and in sync with the boot code patches.

# Upgrades
The patch manager is designed for easy upgradeability in mind. Every release contains the initial installer executable along with an `UPDATE.8xv`. Send the `UPDATE.8xv` to your calculator and enter the patch manager to apply the update. This eliminates the need to physically reflash your flash chip.

You may also remove the patches at any time (while keeping the patch manager installed).

# KhiCAS
KhiCAS is the largest app on the, taking up about 100% of the original archive space. Because of this, clever hacks were used in order to even fit the program (such as stripping the relocation table.) This means that the custom app installer that KhiCAS uses will NOT work with this, since it's designed to unload at a hardcoded location without a relocation table. To use KhiCAS, you need to generatge 

# How it works
The patch manager:

- Modifies [Flash address mask](#flash-address-mask) to map the expanded flash area.
- Updates the constants used to calculate the size of the archive.
- Allows the WriteFlash and EraseFlash routines to write past the original flash area.
- Modifies [NextFlashPage](#nextflashpage--prevflashpage) and [PrevFlashPage](#nextflashpage--prevflashpage) routines to jump over [sectors 3B-3F](#sectors-3b-3f).
- Updates [ArcChk](#arcchk) to exclude [sectors 3B-3F](#sectors-3b-3f) from archive size.
- Prevents marking extended sectors after garbage after transfers.
- Modifies the boot/OS erase code to erase the expanded sectors.
- Relocates the app region to the bottom of the extended flash.
- Restricts apps from growing into [sectors 3B-3F](#sectors-3b-3f) by moving the top of the app region to sector 40.
- Fixes the `Draw32` routine to continue to the millions unit instead of overflowing to 0 after 9999K so the archive size can be displayed properly.

Other stuff:
- Disables OS signature checking in order to boot a patched OS.
- Disables app signature checking (only during transfers) to install large apps like KhiCAS that the 3rd party app installers are not yet able to create properly. This also has the added bonus of allowing you to send a shell like Cesium to execute assembly programs without the need for ArTIfiCE.

<details>
<summary><strong id="flash-address-mask">Flash address mask</strong></summary>
The CE ASIC supports mapping up to 12MB of flash. By default, only addresses 000000 to 3FFFFF are mapped (4MB). There is 8MB of unmapped memory 400000-BFFFFF. The 32-bit flash address mask defines the amount of flash to map. By default, it is set to map ~(FFC00000) = 3FFFFF. The manager changes this mask depending on the amount flash we want to map.
</details>

<details>
<summary><strong id="sectors-3b-3f">Sectors 3B-3F</strong></summary>
These sectors are reserved and are not used for the archive. They are placed at the end of the original 4MB address space.

- Sector 3B is reserved for holding the certificate, a region used to store data that should persist between OS installs (e.g selected language and minimum OS version).

- Sectors 3C-3F are used as a RAM backup in the OS during deep sleep mode.

- Sector 3F is also used as a swap sector when performing flash defragmentation.

These sectors are also read/written to from a few 3rd party programs such as [Cesium](https://github.com/mateoconlechuga/cesium/blob/master/src/flash.asm) and [Cermastr](https://tiplanet.org/forum/archives_voir.php?id=1581757), therefore, they will remain in sectors 3B-3F to maintain compatibility with these programs.
</details>

<details>
<summary><strong id="arcchk">ArcChk</strong></summary> 
ArcChk is a routine that is used to calculate the current size of the archive. Because we skipped sectors 3B-3F, we need to patch the routine to subtract 5 from the total sectors count.
</details>

<details>
<summary><strong id="nextflashpage--prevflashpage">NextFlashPage / PrevFlashPage</strong></summary> 
These routines are used by the archive code to increment / decrement the current flash sector. Conveniently, the archive is sector aligned, meaning that data in one sector can’t continue writing into the next sector. This means that we can simply modify these routines to jump over sectors without any issues.
</details>

# Building
Simply run `make` in the base directory. A `ce-rom-patcher` executable and an `UPDATE.8xv` will be generated.

If you prefer to keep the boot code unlocked, run `make LOCK_BOOT=0` instead.
 
# Disclaimer
Although during my testing I have encountered no issues, there is always the rare possibility that an accident occurs and requires you to reflash the chip for the device to become usable again. The program tries to take great care of the boot sectors by write locking them outside the patch manager to reduce the chances of corruption. The most important thing is to ensure that the device doesn't lose power during the patching process (and especially not when it's writing sectors 00 and 01).

# TODO
The form factor of these serial flash chips can support capacities of up to 32 MB, yet only 12 MB can be mapped at a time, leaving 20 MB unused. It would be nice to have the option to back up the archive/OS into non mappable regions of the flash chip and swap them out when needed. Maybe there are even some secret ports that would allow you to change the base memory mapping address so the swapping process wouldn't be so slow.
