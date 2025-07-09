onbreak {quit -force}
onerror {quit -force}

asim +access +r +m+div_gen_xlslice_0_0 -L xpm -L xlslice_v1_0_2 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.div_gen_xlslice_0_0 xil_defaultlib.glbl

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure

do {div_gen_xlslice_0_0.udo}

run -all

endsim

quit -force
