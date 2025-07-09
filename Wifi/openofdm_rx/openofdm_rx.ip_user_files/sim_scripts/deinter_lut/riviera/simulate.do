onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+deinter_lut -L xpm -L blk_mem_gen_v8_4_4 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.deinter_lut xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {deinter_lut.udo}

run -all

endsim

quit -force
