onbreak {quit -f}
onerror {quit -f}

vsim -lib xil_defaultlib rot_lut_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {rot_lut.udo}

run -all

quit -force
