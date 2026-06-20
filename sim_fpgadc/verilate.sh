clear
rm out/Vsim*
verilator --public --compiler msvc --converge-limit 2000 -Wno-UNSIGNED -Wno-PINMISSING -Wno-WIDTH --exe sim_main.cpp -I. -I.. -Ish4 -I../rtl -I../rtl/cpu -I../rtl/fpu -I../rtl/pvr --top-module simtop -Mdir out --cc simtop.v
