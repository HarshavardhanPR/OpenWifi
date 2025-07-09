-makelib ies_lib/xpm -sv \
  "D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
  "D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_fifo/hdl/xpm_fifo.sv" \
  "D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
-endlib
-makelib ies_lib/xpm \
  "D:/Apps/v_log/Vivado/2021.1/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/blk_mem_gen_v8_4_4 \
  "../../../ipstatic/simulation/blk_mem_gen_v8_4.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../../ip_repo/deinter_lut/sim/deinter_lut.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

