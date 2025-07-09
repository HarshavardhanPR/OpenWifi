onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+atan_lut -L xpm -L blk_mem_gen_v8_4_4 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.atan_lut xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {atan_lut.udo}

run -all

endsim

quit -force
