vlib work
vlib activehdl

vlib activehdl/xpm
vlib activehdl/xlslice_v1_0_2
vlib activehdl/xil_defaultlib

vmap xpm activehdl/xpm
vmap xlslice_v1_0_2 activehdl/xlslice_v1_0_2
vmap xil_defaultlib activehdl/xil_defaultlib

vlog -work xpm  -sv2k12 \
"D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
"D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
"D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \

vcom -work xpm -93 \
"D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xlslice_v1_0_2  -v2k5 \
"../../../ipstatic/ipshared/11d0/hdl/xlslice_v1_0_vl_rfs.v" \

vlog -work xil_defaultlib  -v2k5 \
"../../../../../ip_repo/div_gen_new/src/div_gen_xlslice_0_0/sim/div_gen_xlslice_0_0.v" \

vlog -work xil_defaultlib \
"glbl.v"

