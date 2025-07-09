// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module div_gen (
  quotient,
  dividend,
  divisor,
  clk,
  input_strobe,
  output_strobe
);

  (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 DATA.QUOTIENT DATA" *)
  (* X_INTERFACE_MODE = "master DATA.QUOTIENT" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME DATA.QUOTIENT, LAYERED_METADATA undef" *)
  output [31:0]quotient;
  (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 DATA.DIVIDEND DATA" *)
  (* X_INTERFACE_MODE = "slave DATA.DIVIDEND" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME DATA.DIVIDEND, LAYERED_METADATA undef" *)
  input [31:0]dividend;
  (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 DATA.DIVISOR DATA" *)
  (* X_INTERFACE_MODE = "slave DATA.DIVISOR" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME DATA.DIVISOR, LAYERED_METADATA undef" *)
  input [23:0]divisor;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.CLK CLK" *)
  (* X_INTERFACE_MODE = "slave CLK.CLK" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.CLK, FREQ_HZ 200000000, FREQ_TOLERANCE_HZ 0, PHASE 0.000, CLK_DOMAIN div_gen_clk, INSERT_VIP 0" *)
  input clk;
  (* X_INTERFACE_IGNORE = "true" *)
  input input_strobe;
  (* X_INTERFACE_IGNORE = "true" *)
  output output_strobe;

  // stub module has no contents

endmodule
