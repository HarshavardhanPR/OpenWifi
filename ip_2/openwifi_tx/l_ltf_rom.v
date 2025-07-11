/*
 * Legacy long_preamble_rom - TODO
 *
 * Michael Tetemke Mehari michael.mehari@ugent.be
 * Xianjun Jiao xianjun.jiao@imec.be putaoshu@msn.com
 */
//`include "openofdm_tx_pre_def.v"

module l_ltf_rom
(
  input      [7:0]  addr,
  output reg [31:0] dout  
);

  always @ *
    case (addr)
              0:   dout = 32'hEC000000;
              1:   dout = 32'h0193F382;
              2:   dout = 32'h0BBDF273;
              3:   dout = 32'hF43DF143;
              4:   dout = 32'hFFA4F91E;
              5:   dout = 32'h099C097A;
              6:   dout = 32'hEFB402A0;
              7:   dout = 32'hF066021F;
              8:   dout = 32'hFB841350;
              9:   dout = 32'hF8C602CA;
             10:   dout = 32'hF848F598;
             11:   dout = 32'h08E7FE31;
             12:   dout = 32'h0A86F42E;
             13:   dout = 32'hEF33F7A7;
             14:   dout = 32'hF8ADFAF8;
             15:   dout = 32'h04BAF369;
             16:   dout = 32'h08000800;
             17:   dout = 32'h0F430086;
             18:   dout = 32'hFD1FEB70;
             19:   dout = 32'h078201EA;
             20:   dout = 32'h0322077E;
             21:   dout = 32'hEE7D0611;
             22:   dout = 32'h00200EB8;
             23:   dout = 32'h06D4FF7A;
             24:   dout = 32'h0C7C0350;
             25:   dout = 32'hFB180D97;
             26:   dout = 32'hF1430710;
             27:   dout = 32'h07A80B3A;
             28:   dout = 32'h02B4FC6E;
             29:   dout = 32'h0C65F567;
             30:   dout = 32'h05170E3A;
             31:   dout = 32'hFF580F67;
             32:   dout = 32'h14000000;
             33:   dout = 32'hFF58F099;
             34:   dout = 32'h0517F1C6;
             35:   dout = 32'h0C650A99;
             36:   dout = 32'h02B40392;
             37:   dout = 32'h07A8F4C6;
             38:   dout = 32'hF143F8F0;
             39:   dout = 32'hFB18F269;
             40:   dout = 32'h0C7CFCB0;
             41:   dout = 32'h06D40086;
             42:   dout = 32'h0020F148;
             43:   dout = 32'hEE7DF9EF;
             44:   dout = 32'h0322F882;
             45:   dout = 32'h0782FE16;
             46:   dout = 32'hFD1F1490;
             47:   dout = 32'h0F43FF7A;
             48:   dout = 32'h0800F800;
             49:   dout = 32'h04BA0C97;
             50:   dout = 32'hF8AD0508;
             51:   dout = 32'hEF330859;
             52:   dout = 32'h0A860BD2;
             53:   dout = 32'h08E701CF;
             54:   dout = 32'hF8480A68;
             55:   dout = 32'hF8C6FD36;
             56:   dout = 32'hFB84ECB0;
             57:   dout = 32'hF066FDE1;
             58:   dout = 32'hEFB4FD60;
             59:   dout = 32'h099CF686;
             60:   dout = 32'hFFA406E2;
             61:   dout = 32'hF43D0EBD;
             62:   dout = 32'h0BBD0D8D;
             63:   dout = 32'h01930C7E;
             64:   dout = 32'hEC000000;
             65:   dout = 32'h0193F382;
             66:   dout = 32'h0BBDF273;
             67:   dout = 32'hF43DF143;
             68:   dout = 32'hFFA4F91E;
             69:   dout = 32'h099C097A;
             70:   dout = 32'hEFB402A0;
             71:   dout = 32'hF066021F;
             72:   dout = 32'hFB841350;
             73:   dout = 32'hF8C602CA;
             74:   dout = 32'hF848F598;
             75:   dout = 32'h08E7FE31;
             76:   dout = 32'h0A86F42E;
             77:   dout = 32'hEF33F7A7;
             78:   dout = 32'hF8ADFAF8;
             79:   dout = 32'h04BAF369;
             80:   dout = 32'h08000800;
             81:   dout = 32'h0F430086;
             82:   dout = 32'hFD1FEB70;
             83:   dout = 32'h078201EA;
             84:   dout = 32'h0322077E;
             85:   dout = 32'hEE7D0611;
             86:   dout = 32'h00200EB8;
             87:   dout = 32'h06D4FF7A;
             88:   dout = 32'h0C7C0350;
             89:   dout = 32'hFB180D97;
             90:   dout = 32'hF1430710;
             91:   dout = 32'h07A80B3A;
             92:   dout = 32'h02B4FC6E;
             93:   dout = 32'h0C65F567;
             94:   dout = 32'h05170E3A;
             95:   dout = 32'hFF580F67;
             96:   dout = 32'h14000000;
             97:   dout = 32'hFF58F099;
             98:   dout = 32'h0517F1C6;
             99:   dout = 32'h0C650A99;
            100:   dout = 32'h02B40392;
            101:   dout = 32'h07A8F4C6;
            102:   dout = 32'hF143F8F0;
            103:   dout = 32'hFB18F269;
            104:   dout = 32'h0C7CFCB0;
            105:   dout = 32'h06D40086;
            106:   dout = 32'h0020F148;
            107:   dout = 32'hEE7DF9EF;
            108:   dout = 32'h0322F882;
            109:   dout = 32'h0782FE16;
            110:   dout = 32'hFD1F1490;
            111:   dout = 32'h0F43FF7A;
            112:   dout = 32'h0800F800;
            113:   dout = 32'h04BA0C97;
            114:   dout = 32'hF8AD0508;
            115:   dout = 32'hEF330859;
            116:   dout = 32'h0A860BD2;
            117:   dout = 32'h08E701CF;
            118:   dout = 32'hF8480A68;
            119:   dout = 32'hF8C6FD36;
            120:   dout = 32'hFB84ECB0;
            121:   dout = 32'hF066FDE1;
            122:   dout = 32'hEFB4FD60;
            123:   dout = 32'h099CF686;
            124:   dout = 32'hFFA406E2;
            125:   dout = 32'hF43D0EBD;
            126:   dout = 32'h0BBD0D8D;
            127:   dout = 32'h01930C7E;
            128:   dout = 32'hEC000000;
            129:   dout = 32'h0193F382;
            130:   dout = 32'h0BBDF273;
            131:   dout = 32'hF43DF143;
            132:   dout = 32'hFFA4F91E;
            133:   dout = 32'h099C097A;
            134:   dout = 32'hEFB402A0;
            135:   dout = 32'hF066021F;
            136:   dout = 32'hFB841350;
            137:   dout = 32'hF8C602CA;
            138:   dout = 32'hF848F598;
            139:   dout = 32'h08E7FE31;
            140:   dout = 32'h0A86F42E;
            141:   dout = 32'hEF33F7A7;
            142:   dout = 32'hF8ADFAF8;
            143:   dout = 32'h04BAF369;
            144:   dout = 32'h08000800;
            145:   dout = 32'h0F430086;
            146:   dout = 32'hFD1FEB70;
            147:   dout = 32'h078201EA;
            148:   dout = 32'h0322077E;
            149:   dout = 32'hEE7D0611;
            150:   dout = 32'h00200EB8;
            151:   dout = 32'h06D4FF7A;
            152:   dout = 32'h0C7C0350;
            153:   dout = 32'hFB180D97;
            154:   dout = 32'hF1430710;
            155:   dout = 32'h07A80B3A;
            156:   dout = 32'h02B4FC6E;
            157:   dout = 32'h0C65F567;
            158:   dout = 32'h05170E3A;
            159:   dout = 32'hFF580F67;

          default: dout = 32'h00000000;
    endcase

endmodule
