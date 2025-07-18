`include "common_defs.v"

module equalizer
(
    input clock,
    input enable,
    input reset,

    input reset_dot11,

    input [31:0] sample_in,
    input sample_in_strobe,
    input ht_next,
    input pkt_ht,
    input ht_smoothing,
    input wire disable_all_smoothing,

    output [31:0] phase_in_i,
    output [31:0] phase_in_q,
    output reg phase_in_stb,
    input [15:0] phase_out,
    input phase_out_stb,

    output [`ROTATE_LUT_LEN_SHIFT-1:0] rot_addr,
    input [31:0] rot_data,

    output reg [31:0] sample_out,
    output reg sample_out_strobe,
    
    output reg [3:0] state,

    // for side channel
    output wire [31:0] csi,
    output wire csi_valid,
    output o_csi_data_sbc_valid,
    output o_noiseEst_stb,
    output signed [31:0] o_noiseEst
);

// mask[0] is DC, mask[1:26] -> 1,..., 26
// mask[38:63] -> -26,..., -1
localparam SUBCARRIER_MASK =
    64'b1111111111111111111111111100000000000111111111111111111111111110;

localparam HT_SUBCARRIER_MASK =
    64'b1111111111111111111111111111000000011111111111111111111111111110;

// -7, -21, 21, 7
localparam PILOT_MASK =
    64'b0000001000000000000010000000000000000000001000000000000010000000;

localparam DATA_SUBCARRIER_MASK =
    SUBCARRIER_MASK ^ PILOT_MASK;

localparam HT_DATA_SUBCARRIER_MASK = 
    HT_SUBCARRIER_MASK ^ PILOT_MASK;

// -1,..,-26, 26,..,1
localparam LTS_REF =
    64'b0000101001100000010100110000000000000000010101100111110101001100;

localparam HT_LTS_REF =
    64'b0000101001100000010100110000000000011000010101100111110101001100;

localparam POLARITY = 
    127'b1111111000111011000101001011111010101000010110111100111001010110011000001101101011101000110010001000000100100110100111101110000;

// 21, 7, -7, -21
localparam HT_POLARITY = 4'b1000;

localparam IN_BUF_LEN_SHIFT = 6;

localparam S_FIRST_LTS = 0;
localparam S_SECOND_LTS = 1;
localparam S_SMOOTH_ACTSC = 2;
localparam S_GET_POLARITY = 3;
localparam S_CPE_ESTIMATE = 4;
localparam S_ALL_SC_PE_CORRECTION = 5;
localparam S_HT_LTS = 6;

localparam S_SMOOTH_EDGE = 0;
localparam S_SMOOTH_FIRST_HALF = 1;
localparam S_SMOOTH_SND_HALF = 2 ;
localparam S_SMOOTH_LAST_SC = 3;

reg enable_delay;
wire reset_internal = (enable==0 && enable_delay==1);//reset internal after the module is disabled in case the disable lock the state/stb to a non-end state.

reg ht;
reg [5:0] num_data_carrier;
// in principle: need 11 bits: log2((16+(2^12)*8+6)/24) = 10.4160. Max 2^12 bytes in case of legacy. 16 service bits. 6 tail bits.. 24 MCS0 N_DBPS
// but here we only use till 5. so we can use 3 bits and saturation operation.
reg [2:0] num_ofdm_sym;

wire [5:0] edge_sc_end, edge_sc_init;
assign edge_sc_end = ht? 28:26;
assign edge_sc_init = ht? 38:40;

// bit masks
reg [63:0] lts_ref;
reg [63:0] ht_lts_ref;
reg [63:0] subcarrier_mask;
reg [63:0] data_subcarrier_mask;
reg [63:0] pilot_mask;
reg [5:0] pilot_loc[3:0];
reg signed [5:0] pilot_idx[3:0];
localparam pilot_loc1 = 7;
localparam pilot_loc2 = 21;
localparam pilot_loc3 = 43; 
localparam pilot_loc4 = 57; 
localparam signed pilot_idx1 = 8; 
localparam signed pilot_idx2 = 22; 
localparam signed pilot_idx3 = -20;
localparam signed pilot_idx4 = -6; 
initial begin 
    pilot_loc[0] = pilot_loc1;
    pilot_idx[0] = pilot_idx1;
    pilot_loc[1] = pilot_loc2;
    pilot_idx[1] = pilot_idx2;
    pilot_loc[2] = pilot_loc3;
    pilot_idx[2] = pilot_idx3;
    pilot_loc[3] = pilot_loc4;
    pilot_idx[3] = pilot_idx4;
end

reg [126:0] polarity;
reg [3:0] ht_polarity;
reg [3:0] current_polarity;
reg [3:0] pilot_count1, pilot_count2, pilot_count3;

reg signed [15:0] input_i;
reg signed [15:0] input_q;

reg current_sign;

wire signed [15:0] new_lts_i;
wire signed [15:0] new_lts_q;
wire new_lts_stb;

reg calc_mean_strobe;

reg [5:0] lts_waddr;
reg [6:0] lts_raddr; // one bit wider to detect overflow
reg [15:0] lts_i_in;
reg [15:0] lts_q_in;
reg lts_in_stb;
wire signed [15:0] lts_i_out;
wire signed [15:0] lts_q_out;
wire signed [15:0] lts_q_out_neg = ~lts_q_out + 1;

reg [5:0] in_waddr;
reg [6:0] in_raddr;
wire [15:0] buf_i_out;
wire [15:0] buf_q_out;

reg pilot_in_stb;
wire signed [31:0] pilot_i;
wire signed [31:0] pilot_q;
reg signed [31:0] pilot_i_reg, pilot_q_reg;

reg signed [31:0] pilot_sum_i;
reg signed [31:0] pilot_sum_q;

assign phase_in_i = pilot_i_reg;
assign phase_in_q = pilot_q_reg;

reg signed [15:0] cpe; // common phase error due to RFO
reg signed [7:0] sym_idx;
wire signed [15:0] sym_phase;
assign sym_phase = (cpe > 1608) ? (cpe - 3217) : ((cpe < -1608) ? (cpe + 3217) : cpe);//only taking [15:0] to rotate could have overflow!

reg rot_in_stb;
wire signed [15:0] rot_i;
wire signed [15:0] rot_q;

wire [31:0] mag_sq;
wire [31:0] prod_i;
wire [31:0] prod_q;
wire [31:0] prod_i_scaled = prod_i<<(`CONS_SCALE_SHIFT+1);
wire [31:0] prod_q_scaled = prod_q<<(`CONS_SCALE_SHIFT+1); // +1 to fix the bug threshold for demodulate.v

reg signed [15:0] lts_reg1_i, lts_reg2_i, lts_reg3_i;
reg signed [15:0] lts_reg1_q, lts_reg2_q, lts_reg3_q;
wire signed [18:0] lts_sum_1_3_i = lts_reg1_i + lts_reg2_i + lts_reg3_i;
wire signed [18:0] lts_sum_1_3_q = lts_reg1_q + lts_reg2_q + lts_reg3_q;
reg signed [18:0] lts_sum_i;
reg signed [18:0] lts_sum_q;
reg [1:0] smooth_state, smooth_state_dl;
reg [1:0] delay_cnt; 

reg [2:0] lts_mv_avg_len;
reg lts_div_in_stb;

reg prod_in_strobe;
wire prod_out_strobe;

wire [31:0] dividend_i = (state == S_SMOOTH_ACTSC) ? (lts_sum_i[18] == 0 ? {13'h0,lts_sum_i} : {13'h1FFF,lts_sum_i}) : (state == S_ALL_SC_PE_CORRECTION ? prod_i_scaled : 0);
wire [31:0] dividend_q = (state == S_SMOOTH_ACTSC) ? (lts_sum_q[18] == 0 ? {13'h0,lts_sum_q} : {13'h1FFF,lts_sum_q}) : (state == S_ALL_SC_PE_CORRECTION ? prod_q_scaled : 0);
wire [23:0] divisor_i = (state == S_SMOOTH_ACTSC) ? {21'b0,lts_mv_avg_len} : (state == S_ALL_SC_PE_CORRECTION ? mag_sq[23:0] : 1);
wire [23:0] divisor_q = (state == S_SMOOTH_ACTSC) ? {21'b0,lts_mv_avg_len} : (state == S_ALL_SC_PE_CORRECTION ? mag_sq[23:0] : 1);
wire div_in_stb = (state == S_SMOOTH_ACTSC) ? lts_div_in_stb : (state == S_ALL_SC_PE_CORRECTION ? prod_out_strobe : 0);

reg [15:0] num_output;
wire [31:0] quotient_i;
wire [31:0] quotient_q;
wire [31:0] norm_i = quotient_i;
wire [31:0] norm_q = quotient_q;
wire [31:0] lts_div_i = quotient_i;
wire [31:0] lts_div_q = quotient_q;

wire div_out_stb;
wire norm_out_stb = div_out_stb;
wire lts_div_out_stb = div_out_stb;

// for side channel
reg sample_in_strobe_dly;
assign csi_valid = ( (num_ofdm_sym == 1 || (pkt_ht==1 && num_ofdm_sym==5)) && state == S_CPE_ESTIMATE && sample_in_strobe_dly == 1 && enable && (~reset) );
wire csi_data_sbc_valid = ((csi_valid == 1) && ((HT_DATA_SUBCARRIER_MASK[lts_raddr-1] && pkt_ht==1)||(DATA_SUBCARRIER_MASK[lts_raddr-1] && pkt_ht==0))) ? 1 : 0;
assign csi = csi_valid ? {lts_i_out, lts_q_out} : 0;


/////////////////////////////////
// Noise Variance Calc

wire signed [15:0] noise_i;
wire signed [15:0] noise_q;
assign noise_i = lts_i_out - input_i;
assign noise_q = lts_q_out - input_q;
reg signed [37:0] noise_i_sq_sum;
reg signed [37:0] noise_q_sq_sum;

reg calc_mean_strobe_dly;
wire noiseEst_in_stb = (~calc_mean_strobe && calc_mean_strobe_dly);
wire noiseEst_out_stb;
wire signed [31:0] noiseEst;

wire s_check_noiseest_sbc = (calc_mean_strobe && SUBCARRIER_MASK[lts_raddr-1]);

assign o_noiseEst_stb = noiseEst_out_stb;
assign o_noiseEst = (noiseEst==0?1:noiseEst);
assign o_csi_data_sbc_valid = csi_data_sbc_valid;

always @(posedge clock ) begin
  if (reset) begin
    calc_mean_strobe_dly <= 0;
  end else begin
    if (enable) begin
      calc_mean_strobe_dly <= calc_mean_strobe;
    end
  end
end

complex_to_mag #(.DATA_WIDTH(32)) noiseEst_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .i(noise_i_sq_sum[31:0]),
    .q(noise_q_sq_sum[31:0]),
    .input_strobe(noiseEst_in_stb),
    .mag(noiseEst),
    .mag_stb(noiseEst_out_stb)
);
/////////////////////////////////////

always @(posedge clock) begin
    if (reset) begin
        enable_delay <= 0;
    end else begin
        enable_delay <= enable;
    end
end

dpram #(.DATA_WIDTH(32), .ADDRESS_WIDTH(6)) lts_inst (
    .clock(clock),
    .reset(reset_dot11),
    .enable_a(1),
    .write_enable(lts_in_stb),
    .write_address(lts_waddr),
    .write_data({lts_i_in, lts_q_in}),
    .read_data_a(),
    .enable_b(1),
    .read_address(lts_raddr[5:0]),
    .read_data({lts_i_out, lts_q_out})
);

calc_mean lts_i_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),
    
    .a(lts_i_out),
    .b(input_i),
    .sign(current_sign),
    .input_strobe(calc_mean_strobe),

    .c(new_lts_i),
    .output_strobe(new_lts_stb)
);

calc_mean lts_q_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),
    
    .a(lts_q_out),
    .b(input_q),
    .sign(current_sign),
    .input_strobe(calc_mean_strobe),

    .c(new_lts_q)
);

dpram  #(.DATA_WIDTH(32), .ADDRESS_WIDTH(6)) in_buf_inst (
    .clock(clock),
    .reset(reset_dot11),
    .enable_a(1),
    .write_enable(sample_in_strobe),
    .write_address(in_waddr),
    .write_data(sample_in),
    .read_data_a(),
    .enable_b(1),
    .read_address(in_raddr[5:0]),
    .read_data({buf_i_out, buf_q_out})
);

complex_mult pilot_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),
    .a_i(input_i),
    .a_q(input_q),
    .b_i(lts_i_out),
    .b_q(lts_q_out),
    .input_strobe(pilot_in_stb),
    .p_i(pilot_i),
    .p_q(pilot_q),
    .output_strobe(pilot_out_stb)
);

rotate rotate_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),

    .in_i(buf_i_out),
    .in_q(buf_q_out),
    .phase(sym_phase),
    .input_strobe(rot_in_stb),

    .rot_addr(rot_addr),
    .rot_data(rot_data),
    
    .out_i(rot_i),
    .out_q(rot_q),
    .output_strobe(rot_out_stb)
);

complex_mult input_lts_prod_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),
    .a_i(rot_i),
    .a_q(rot_q),
    .b_i(lts_i_out),
    .b_q(lts_q_out_neg),
    .input_strobe(rot_out_stb),
    .p_i(prod_i),
    .p_q(prod_q),
    .output_strobe(prod_out_strobe)
);

complex_mult lts_lts_prod_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),
    .a_i(lts_i_out),
    .a_q(lts_q_out),
    .b_i(lts_i_out),
    .b_q(lts_q_out_neg),
    .input_strobe(rot_out_stb),
    .p_i(mag_sq)
);

divider norm_i_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),

    .dividend(dividend_i),
    .divisor(divisor_i),
    .input_strobe(div_in_stb),

    .quotient(quotient_i),
    .output_strobe(div_out_stb)
);

divider norm_q_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset|reset_internal),

    .dividend(dividend_q),
    .divisor(divisor_q),
    .input_strobe(div_in_stb),

    .quotient(quotient_q)
);

always @(posedge clock) begin
    if (reset|reset_internal) begin
        sample_in_strobe_dly <= sample_in_strobe;
        sample_out_strobe <= 0;
        lts_raddr <= 0;
        lts_waddr <= 0;
        sample_out <= 0;

        lts_in_stb <= 0;
        lts_i_in <= 0;
        lts_q_in <= 0;

        ht <= 0;
        num_data_carrier <= 48;
        num_ofdm_sym <= 0;

        subcarrier_mask <= SUBCARRIER_MASK;
        data_subcarrier_mask <= DATA_SUBCARRIER_MASK;
        pilot_mask <= PILOT_MASK;
        lts_ref <= LTS_REF;
        ht_lts_ref <= HT_LTS_REF;
        polarity <= POLARITY;

        ht_polarity <= HT_POLARITY;

        current_polarity <= 0;
        pilot_count1 <= 0;
        pilot_count2 <= 0;
        pilot_count3 <= 0; 

        in_waddr <= 0;
        in_raddr <= 0;
        sym_idx <= 0;

        lts_reg1_i <= 0; lts_reg2_i <= 0; lts_reg3_i <= 0; 
        lts_reg1_q <= 0; lts_reg2_q <= 0; lts_reg3_q <= 0; 
        lts_sum_i <= 0;
        lts_sum_q <= 0;
        lts_mv_avg_len <= 0;
        lts_div_in_stb <= 0;
        smooth_state <= 0;
        smooth_state_dl <= 0 ;
        delay_cnt <= 0;

        phase_in_stb <= 0;
        pilot_sum_i <= 0;
        pilot_sum_q <= 0;
        cpe <= 0;
        pilot_in_stb <= 0;
        pilot_i_reg <= 0;
        pilot_q_reg <= 0;

        prod_in_strobe <= 0;

        rot_in_stb <= 0;

        current_sign <= 0;
        input_i <= 0;
        input_q <= 0;
        calc_mean_strobe <= 0;

        num_output <= 0;

        noise_i_sq_sum <= 0;
        noise_q_sq_sum <= 0;

        state <= S_FIRST_LTS;
    end else if (enable) begin
        sample_in_strobe_dly <= sample_in_strobe;
        smooth_state_dl <= smooth_state;
        case(state)
            S_FIRST_LTS: begin
                // store first LTS as is
                lts_in_stb <= sample_in_strobe;
                {lts_i_in, lts_q_in} <= sample_in;

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 0;
                        lts_raddr <= 0;
                        state <= S_SECOND_LTS;
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end
            end

            S_SECOND_LTS: begin
                // calculate and store the mean of the two LTS
                if (sample_in_strobe) begin
                    calc_mean_strobe <= sample_in_strobe;
                    {input_i, input_q} <= sample_in;
                    current_sign <= lts_ref[0];
                    lts_ref <= {lts_ref[0], lts_ref[63:1]};
                    lts_raddr <= lts_raddr + 1;
                end else begin
                    calc_mean_strobe <= 0;
                end

                ////////////////
                // Noise Variance calculation
                if(calc_mean_strobe) begin
                  if (SUBCARRIER_MASK[lts_raddr-1]) begin
                    noise_i_sq_sum <= noise_i_sq_sum + (noise_i * noise_i);
                    noise_q_sq_sum <= noise_q_sq_sum + (noise_q * noise_q);
                  end
                end
                ////////////////////////

                lts_in_stb <= new_lts_stb;
                {lts_i_in, lts_q_in} <= {new_lts_i, new_lts_q};

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 37;
                        lts_raddr <= 38;
                        lts_in_stb <= 0;
                        lts_div_in_stb <= 0;
                        state <= (disable_all_smoothing?S_GET_POLARITY:S_SMOOTH_ACTSC);
                        smooth_state <= 0;
                        delay_cnt <= 0;
                        lts_mv_avg_len <= 3;
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end
            end 


            S_SMOOTH_ACTSC: begin
                if (smooth_state == S_SMOOTH_EDGE) begin
                    if (smooth_state_dl == S_SMOOTH_EDGE) // stay extra clock on the edge 
                        smooth_state <= S_SMOOTH_FIRST_HALF;
                    else if (smooth_state_dl == S_SMOOTH_SND_HALF)
                        smooth_state <= S_SMOOTH_SND_HALF;                     
                end else if (smooth_state == S_SMOOTH_FIRST_HALF) begin // smooth first half
                    lts_raddr <= lts_raddr<63? lts_raddr + 1 : lts_raddr;
                    if (lts_raddr == 63) begin
                        smooth_state <= S_SMOOTH_SND_HALF ;
                    end
                    if (lts_raddr > edge_sc_init) 
                        lts_div_in_stb <= 1;
                 
                end else if (smooth_state == S_SMOOTH_SND_HALF) begin // smooth second half
                    lts_raddr <= lts_raddr == 63? 1: ( lts_raddr<edge_sc_end? lts_raddr + 1 : lts_raddr); 
                    if (lts_raddr == 63) 
                        smooth_state <= S_SMOOTH_EDGE ;
                    else if (lts_raddr == edge_sc_end) begin
                        smooth_state <= S_SMOOTH_LAST_SC ;
                        delay_cnt <= 0;
                    end                    
                    if (lts_raddr == 63 || lts_raddr == 1 || lts_raddr > 3)  
                        lts_div_in_stb <= 1;
                    else
                        lts_div_in_stb <= 0;           
                end else begin // stay on the last SC to wait for sum_i, sum_q gets right value
                    delay_cnt <= delay_cnt < 3? delay_cnt + 1 : delay_cnt;
                    if (delay_cnt == 3) 
                        lts_div_in_stb <= 0 ;
                end
                lts_reg1_i <= lts_i_out; lts_reg2_i <= lts_reg1_i; lts_reg3_i <= lts_reg2_i; 
                lts_reg1_q <= lts_q_out; lts_reg2_q <= lts_reg1_q; lts_reg3_q <= lts_reg2_q; 
                lts_sum_i <= lts_sum_1_3_i;
                lts_sum_q <= lts_sum_1_3_q;
                if(lts_div_out_stb == 1) begin
                    lts_i_in <= lts_div_i[15:0];
                    lts_q_in <= lts_div_q[15:0];
                    lts_waddr[5:0] <= (lts_waddr[5:0] == 63)? 1: lts_waddr[5:0] + 1;
                end
                lts_in_stb <= lts_div_out_stb;
                if(lts_waddr == edge_sc_end) begin
                    state <= S_GET_POLARITY;
                end
            end
                      
            S_GET_POLARITY: begin
                // obtain the polarity of pilot sub-carriers for next OFDM symbol
                if (ht) begin
                    current_polarity <= {
                        ht_polarity[1]^polarity[0], // -7
                        ht_polarity[0]^polarity[0], // -21
                        ht_polarity[3]^polarity[0], // 21
                        ht_polarity[2]^polarity[0]  // 7
                        };
                    ht_polarity <= {ht_polarity[0], ht_polarity[3:1]};
                end else begin
                    current_polarity <= {
                        polarity[0],    // -7
                        polarity[0],    // -21
                        ~polarity[0],   // 21
                        polarity[0]     // 7
                        };
                end
                polarity <= {polarity[0], polarity[126:1]};

                pilot_sum_i <= 0;
                pilot_sum_q <= 0;
                pilot_count1 <= 0;
                pilot_count2 <= 0;
                cpe <= 0;
                in_waddr <= 0;
                in_raddr <= 0;
                input_i <= 0;
                input_q <= 0;
                lts_raddr <= 0;
                num_ofdm_sym <= (num_ofdm_sym == 7? num_ofdm_sym : (num_ofdm_sym + 1));
                state <= S_CPE_ESTIMATE;
            end

            S_CPE_ESTIMATE: begin
                if (~ht & ht_next) begin
                    ht <= 1;
                    num_data_carrier <= 52;
                    lts_waddr <= 0;
                    lts_ref <= HT_LTS_REF;
                    subcarrier_mask <= HT_SUBCARRIER_MASK;
                    data_subcarrier_mask <= HT_DATA_SUBCARRIER_MASK;
                    pilot_mask <= PILOT_MASK;
                    // reverse this extra shift
                    polarity <= {polarity[125:0], polarity[126]};
                    state <= S_HT_LTS;
                end

                // calculate residue freq offset using pilot sub carriers
                if (sample_in_strobe) begin
                    in_waddr <= in_waddr + 1;
                    lts_raddr <= lts_raddr + 1;

                    pilot_mask <= {pilot_mask[0], pilot_mask[63:1]};
                    if (pilot_mask[0]) begin
                        pilot_count1 <= pilot_count1 + 1;
                        // obtain the conjugate of current pilot sub carrier
                        if (current_polarity[pilot_count1] == 0) begin
                            input_i <= sample_in[31:16];
                            input_q <= ~sample_in[15:0] + 1;
                        end else begin
                            input_i <= ~sample_in[31:16] + 1;
                            input_q <= sample_in[15:0];
                        end
                        pilot_in_stb <= 1;
                    end else begin
                        pilot_in_stb <= 0;
                    end
                end else begin
                    pilot_in_stb <= 0;
                end

                if (pilot_out_stb) begin
                    pilot_sum_i <= pilot_sum_i + pilot_i;
                    pilot_sum_q <= pilot_sum_q + pilot_q;
                    pilot_count2 <= pilot_count2 + 1; 
                end else if (pilot_count2 == 4) begin
                    pilot_i_reg <= pilot_sum_i;
                    pilot_q_reg <= pilot_sum_q; 
                    phase_in_stb <= 1;
                    pilot_count2 <= 0; 
                end else begin
                    phase_in_stb <= 0; 
                end

                if (phase_out_stb) begin
                    cpe <= phase_out; 
                    pilot_count1 <= 0; 
                    pilot_count2 <= 0;
                    pilot_count3 <= 0; 
                    in_raddr <= pilot_loc[0][5:0];  // sample in location, compensate for RAM read delay
                    lts_raddr <= pilot_loc[0][5:0]; // LTS location, compensate for RAM read delay
                    in_raddr <= 0; 
                    sym_idx <= 0;
                    // compensate for RAM read delay
                    lts_raddr <= 1;
                    rot_in_stb <= 0;
                    num_output <= 0;
                    state <= S_ALL_SC_PE_CORRECTION;
                end
            end

            S_ALL_SC_PE_CORRECTION: begin
                if (sym_idx < 64) begin
                    sym_idx <= sym_idx + 1;
                    rot_in_stb <= 1;
                    in_raddr <= in_raddr + 1;  
                end else begin
                    rot_in_stb <= 0;
                end


                if (rot_out_stb) begin
                    lts_raddr <= lts_raddr + 1;
                end

                if (norm_out_stb) begin
                    data_subcarrier_mask <= {data_subcarrier_mask[0],
                        data_subcarrier_mask[63:1]};
                    if (data_subcarrier_mask[0]) begin
                        sample_out_strobe <= 1;
                        sample_out <= {norm_i[31], norm_i[14:0],
                            norm_q[31], norm_q[14:0]};
                        num_output <= num_output + 1;
                    end else begin
                        sample_out_strobe <= 0;
                    end
                end else begin
                    sample_out_strobe <= 0;
                end

                if (num_output == num_data_carrier) begin
                    state <= S_GET_POLARITY;
                end
            end

            S_HT_LTS: begin
                if (sample_in_strobe) begin
                    lts_in_stb <= 1;
                    ht_lts_ref <= {ht_lts_ref[0], ht_lts_ref[63:1]};
                    if (ht_lts_ref[0] == 0) begin
                        {lts_i_in, lts_q_in} <= sample_in;
                    end else begin
                        lts_i_in <= ~sample_in[31:16]+1;
                        lts_q_in <= ~sample_in[15:0]+1;
                    end
                end else begin
                    lts_in_stb <= 0;
                end

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 35;
                        lts_raddr <= 36;
                        lts_in_stb <= 0;
                        lts_div_in_stb <= 0;
                        smooth_state <= 0;
                        delay_cnt <= 0;
                        lts_mv_avg_len <= 3;                        
                        // Depending on smoothing bit in HT-SIG, smooth the channel
                        if(ht_smoothing==1 && disable_all_smoothing==0) begin
                            state <= S_SMOOTH_ACTSC;
                        end else begin
                            state <= S_GET_POLARITY;
                        end
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end

            end

            default: begin
                state <= S_FIRST_LTS;
            end
        endcase
    end else begin
        sample_out_strobe <= 0;
    end
end

endmodule
