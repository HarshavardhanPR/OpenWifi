-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
-- Date        : Wed Jul  9 17:48:21 2025
-- Host        : MyASUS running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               c:/Users/ASUS/Downloads/Openofdm/openofdm-dot11zynq/Wifi/ip_repo/div_gen_new/src/div_gen_div_gen_0_0/div_gen_div_gen_0_0_stub.vhdl
-- Design      : div_gen_div_gen_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7z020clg484-1
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity div_gen_div_gen_0_0 is
  Port ( 
    aclk : in STD_LOGIC;
    s_axis_divisor_tvalid : in STD_LOGIC;
    s_axis_divisor_tdata : in STD_LOGIC_VECTOR ( 23 downto 0 );
    s_axis_dividend_tvalid : in STD_LOGIC;
    s_axis_dividend_tdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_dout_tvalid : out STD_LOGIC;
    m_axis_dout_tdata : out STD_LOGIC_VECTOR ( 55 downto 0 )
  );

end div_gen_div_gen_0_0;

architecture stub of div_gen_div_gen_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aclk,s_axis_divisor_tvalid,s_axis_divisor_tdata[23:0],s_axis_dividend_tvalid,s_axis_dividend_tdata[31:0],m_axis_dout_tvalid,m_axis_dout_tdata[55:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "div_gen_v5_1_18,Vivado 2021.1";
begin
end;
