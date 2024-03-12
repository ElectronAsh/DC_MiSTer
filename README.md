# [Dreamcast PVR Testing]
by ElectronAsh.

Special thanks to laxer3a, RTLengineering, dentnz, skmp (reicast), Zephray (SH4 core).
And thanks to many others on the GDROM Emu, The 3DO Community, and Simulant Discord servers.

## Status
This is NOT, I repeat NOT anywhere close to a full "core" right now.

This is just some tests for the low-level part of the PowerVR2 renderer, but also done as a learning experience.

At the start of this process, I didn't think I'd even be able to wrap my brain around parsing the VRAM structs to actually render anything. lol

There is NO promise of a finished core here, but we'll see where it goes.

The test core Quartus project (for MiSTer) is called "S32X" atm, but that's just the core I used as a template, so please ignore the name.

The Verilog is quite rough, and not much more than some state machines right now.

The Verilator sim (in MSVC) is in the sim_fpgadc repo.

The SH4 core is not finished yet either.
The main authors of that core are currently very busy with work etc.
The SH4 core is obviously very complex, so hard for me to debug.
It took me about four days once, just to find ONE instruction bug. lol

The current Verilog for PVR2 can only render the 8MB VRAM dumps taken from reicast.

This is almost "cheating", as it means the (emulated) CPU in reicast has already done most of the 
heavy-lifting of doing the 3D calcs and copying the tetxures into VRAM etc.

There are also issues with the interpolator and half-edge calcs in Verilog.
(The renders used to look a lot better when most of it was still in C code on the sim.)

Only some renders on the FPGA (like larger logos) look OK.
For many other scenes, there are lots of missing polygons, and whole tiles corrupted.

I think that must be an ISP parser bug, most likely related to the DDR request signal timings.

To get a VRAM dump to load when the core is first loaded, you have to copy an example pvr_regs file from the sim_fpgadc repo, from the "out" folder.
Then rename that file to boot0.rom, and copying it onto the MiSTer SD card, in the games/Dreamcast folder.

eg. look in the sim_fpgadc repo "out" folder, for say pvr_regs_menu. Rename that file to boot0.rom , then copy to games/Dreamcast on the SD card.

Do the same thing for vram_menu.bin, but rename that to boot1.rom instead.

You can load other pvr_regs and VRAM dump files via the MiSTer OSD menu.
But you MUST add the .bin extension to all files, else they won't be displayed by the menu.

The pvr_regs file should be loaded first, then the VRAM dump file.

A lot of the dump files won't render nice frames yet.
It will also be very slow, say 12 seconds or more, just to render ONE frame.
I had to disable most of the speed-up logic, else it was trying to use about 226% of the logic on the DE10 Nano. lol

Once the VRAM dump file has fully loaded into DDR3, it will bring the core out of reset, and should begin to render the scene.

The core uses DDR3 for storing the 8MB VRAM dump, but uses the SDRAM module for the display framebuffer.

Only HDMI is working atm, via the ASCAL scaler.
NOTE: The VGA/RGB output will NOT have correct timings for 15KHz nor 31KHz right now, so please be aware not to hook up a CRT monitor!


ElectronAsh.
