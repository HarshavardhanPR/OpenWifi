`include "openofdm_rx_pre_def.v"

`ifdef OPENOFDM_RX_ENABLE_DBG
`define DEBUG_PREFIX (*mark_debug="true",DONT_TOUCH="TRUE"*)
`else
`define DEBUG_PREFIX
`endif

module sync_long (
    input clock,
    input reset,
    input enable,

    input reset_dot11,

    input [31:0] sample_in,
    input sample_in_strobe,
    input short_gi,
    input [3:0] fft_win_shift,

    input [15:0] phase_out,
    input phase_out_stb,

    output [`ROTATE_LUT_LEN_SHIFT-1:0] rot_addr,
    input [31:0] rot_data,

    output [31:0] metric,
    output metric_stb,
    output reg long_preamble_detected,
    
    output [31:0] phase_in_i,
    output [31:0] phase_in_q,
    output phase_in_stb,

    output reg [31:0] sample_out,
    output reg sample_out_strobe,
    output reg [15:0] num_ofdm_symbol, //max 20166 = (22+65535*8)/26

    `DEBUG_PREFIX input phase_offset_override_en,
    `DEBUG_PREFIX input signed [15:0] phase_offset_override_val,
    output wire signed [15:0] phase_offset_taken,
    output wire signed [15:0] ltf_phase_offset,
    output reg [2:0] state
);
`include "common_params.v"

localparam IN_BUF_LEN_SHIFT = 8;

localparam NUM_STS_TAIL = 32;
localparam NUM_ADD_SP_TO_SKIP = 22 ; // skip some more samples to avoid consusion caused by CP
localparam S_SKIPPING_TAIL = 0;
localparam S_SKIPPING_CP = 1;
localparam S_WAIT_FOR_FIRST_PEAK = 2;
localparam S_WAIT_FOR_SECOND_PEAK = 3;
localparam S_IDLE = 4;
localparam S_FFT = 5;

reg reset_delay1;
reg reset_delay2;
reg reset_delay3;
reg reset_delay4;
reg [15:0] in_offset;
reg [IN_BUF_LEN_SHIFT-1:0] in_waddr;
reg [IN_BUF_LEN_SHIFT-1:0] in_raddr;
wire [IN_BUF_LEN_SHIFT-1:0] gi_skip = short_gi? 9: 17;
reg signed [31:0] num_input_produced;
reg signed [31:0] num_input_consumed;
reg signed [31:0] num_input_avail;

reg [2:0] mult_stage;
reg [1:0] sum_stage;
reg  mult_strobe;

wire signed [31:0] stage_sum_i;
wire signed [31:0] stage_sum_q;

wire stage_sum_stb;

reg signed [31:0] sum_i;
reg signed [31:0] sum_q;
reg sum_stb;

reg signed [31:0] phase_correction;
reg signed [31:0] next_phase_correction;

reg reset_delay ; // add reset signal for fft, somehow all kinds of event flag raises when feeding real rf signal, maybe reset will help
wire fft_resetn ;

//`DEBUG_PREFIX wire signed [15:0] phase_offset;
reg signed [15:0] ltf_phase_offset_int;
assign ltf_phase_offset = (phase_offset_override_en?phase_offset_override_val:ltf_phase_offset_int);
assign phase_offset_taken = ltf_phase_offset_int;
wire [31:0] sample_delayed;
wire sample_delayed_stb;

reg [31:0] sample_delayed_conj;
reg sample_delayed_conj_stb;

wire [63:0] prod;
wire prod_stb;

reg [15:0] phase_out_neg;
reg [15:0] phase_offset_neg;

wire sample_delay_enable;
assign sample_delay_enable = (state == S_SKIPPING_CP || state == S_WAIT_FOR_FIRST_PEAK || state == S_WAIT_FOR_SECOND_PEAK)? 1'b1 : 1'b0 ;

always @(posedge clock) begin
    reset_delay = reset ;
end
assign fft_resetn = (~reset) & (~reset_delay); // make sure resetn is at least 2 clock cycles low 

complex_to_mag #(.DATA_WIDTH(32)) sum_mag_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .i(sum_i),
    .q(sum_q),
    .input_strobe(sum_stb),

    .mag(metric),
    .mag_stb(metric_stb)
);

fifo_sample_delay # (.DATA_WIDTH(32), .LOG2_FIFO_DEPTH(7)) sample_delayed_inst (
    .clk(clock),
    .rst(reset|reset_delay1|reset_delay2|reset_delay3|reset_delay4),
    .delay_ctl(64),
    .data_in(sample_in),
    .data_in_valid(sample_in_strobe & sample_delay_enable),
    .data_out(sample_delayed),
    .data_out_valid(sample_delayed_stb)
);

complex_mult delay_prod_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .a_i(sample_in[31:16]),
    .a_q(sample_in[15:0]),
    .b_i(sample_delayed_conj[31:16]),
    .b_q(sample_delayed_conj[15:0]),
    .input_strobe(sample_delayed_conj_stb),

    .p_i(prod[63:32]),
    .p_q(prod[31:0]),
    .output_strobe(prod_stb)
);

mv_avg_dual_ch #(.DATA_WIDTH0(32), .DATA_WIDTH1(32), .LOG2_AVG_LEN(5)) freq_offset_inst (
    .clk(clock),
    .rstn(~(reset|reset_delay1|reset_delay2|reset_delay3|reset_delay4)),
    // .rstn(~reset),
    
    .data_in0(prod[63:32]),
    .data_in1(prod[31:0]),
    .data_in_valid(prod_stb),

    .data_out0(phase_in_i),
    .data_out1(phase_in_q),
    .data_out_valid(phase_in_stb)
);

reg [31:0] metric_max1;
reg [(IN_BUF_LEN_SHIFT-1):0] addr1;

reg [31:0] cross_corr_buf[0:31];

reg [31:0] stage_X0;
reg [31:0] stage_X1;
reg [31:0] stage_X2;
reg [31:0] stage_X3;
reg [31:0] stage_X4;
reg [31:0] stage_X5;
reg [31:0] stage_X6;
reg [31:0] stage_X7;

reg [31:0] stage_Y0;
reg [31:0] stage_Y1;
reg [31:0] stage_Y2;
reg [31:0] stage_Y3;
reg [31:0] stage_Y4;
reg [31:0] stage_Y5;
reg [31:0] stage_Y6;
reg [31:0] stage_Y7;

stage_mult stage_mult_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .X0(stage_X0),
    .X1(stage_X1),
    .X2(stage_X2),
    .X3(stage_X3),
    .X4(stage_X4),
    .X5(stage_X5),
    .X6(stage_X6),
    .X7(stage_X7),

    .Y0(stage_Y0),
    .Y1(stage_Y1),
    .Y2(stage_Y2),
    .Y3(stage_Y3),
    .Y4(stage_Y4),
    .Y5(stage_Y5),
    .Y6(stage_Y6),
    .Y7(stage_Y7),

    .input_strobe(mult_strobe),

    .sum({stage_sum_i, stage_sum_q}),
    .output_strobe(stage_sum_stb)
);

reg fft_start;
//wire fft_start_delayed;

wire fft_in_stb;
reg fft_loading;
wire signed [15:0] fft_in_re;
wire signed [15:0] fft_in_im;
wire signed [15:0] fft_in_re_bitshift;
wire signed [15:0] fft_in_im_bitshift;
wire [22:0] fft_out_re;
wire [22:0] fft_out_im;
wire fft_ready;
wire fft_done;
wire fft_busy;
wire fft_valid;

wire [31:0] fft_out = {fft_out_re[22:7], fft_out_im[22:7]};

wire signed [15:0] raw_i;
wire signed [15:0] raw_q;
reg raw_stb;
wire idle_line1, idle_line2 ;
reg fft_din_data_tlast ;
wire fft_din_data_tlast_delayed ;
wire event_frame_started;
wire event_tlast_unexpected;
wire event_tlast_missing;
wire event_status_channel_halt;
wire event_data_in_channel_halt;
wire event_data_out_channel_halt;
wire s_axis_config_tready;
wire m_axis_data_tlast;

dpram  #(.DATA_WIDTH(32), .ADDRESS_WIDTH(IN_BUF_LEN_SHIFT)) in_buf (
    .clock(clock),
    .reset(reset_dot11),
    .enable_a(1),
    .write_enable(sample_in_strobe),
    .write_address(in_waddr),
    .write_data(sample_in),
    .read_data_a(),
    .enable_b(fft_start | fft_loading),
    .read_address(in_raddr),
    .read_data({raw_i, raw_q})
);

rotate rotate_inst (
    .clock(clock),
    .enable(enable),
    .reset(reset),

    .in_i(raw_i),
    .in_q(raw_q),
    .phase(phase_correction),
    .input_strobe(raw_stb),

    .rot_addr(rot_addr),
    .rot_data(rot_data),
    
    .out_i(fft_in_re),
    .out_q(fft_in_im),
    .output_strobe(fft_in_stb)
);

assign fft_in_re_bitshift = {fft_in_re[15], fft_in_re[13:0],1'b0};
assign fft_in_im_bitshift = {fft_in_im[15], fft_in_im[13:0],1'b0};
delayT #(.DATA_WIDTH(1), .DELAY(10)) fft_delay_inst (
    .clock(clock),
    .reset(reset),

    .data_in(fft_din_data_tlast),
    .data_out(fft_din_data_tlast_delayed)
);

///the fft7_1 isntance is commented out, as it is upgraded to fft9 version
/*xfft_v7_1 dft_inst (
    .clk(clock),
    .fwd_inv(1),
    .start(fft_start_delayed),
    .fwd_inv_we(1),

    .xn_re(fft_in_re),
    .xn_im(fft_in_im),
    .xk_re(fft_out_re),
    .xk_im(fft_out_im),
    .rfd(fft_ready),
    .done(fft_done),
    .busy(fft_busy),
    .dv(fft_valid)
);*/


xfft_v9 dft_inst (
  .aclk(clock),       // input wire aclk
  .aresetn(fft_resetn),                                               
  .s_axis_config_tdata({7'b0, 1'b1}),                          // input wire [7 : 0] s_axis_config_tdata, use LSB to indicate it is forward transform, the rest should be ignored
  .s_axis_config_tvalid(1'b1),                                 // input wire s_axis_config_tvalid
  .s_axis_config_tready(s_axis_config_tready),                // output wire s_axis_config_tready
  .s_axis_data_tdata({fft_in_im_bitshift, fft_in_re_bitshift}),                      // input wire [31 : 0] s_axis_data_tdata
  .s_axis_data_tvalid(fft_in_stb),                    // input wire s_axis_data_tvalid
  .s_axis_data_tready(fft_ready),                    // output wire s_axis_data_tready
  .s_axis_data_tlast(fft_din_data_tlast_delayed),                      // input wire s_axis_data_tlast
  .m_axis_data_tdata({idle_line1,fft_out_im, idle_line2, fft_out_re}),                      // output wire [47 : 0] m_axis_data_tdata
  .m_axis_data_tvalid(fft_valid),                    // output wire m_axis_data_tvalid
  .m_axis_data_tready(1'b1),                    // input wire m_axis_data_tready
  .m_axis_data_tlast(m_axis_data_tlast),                      // output wire m_axis_data_tlast
  .event_frame_started(event_frame_started),                  // output wire event_frame_started
  .event_tlast_unexpected(event_tlast_unexpected),            // output wire event_tlast_unexpected
  .event_tlast_missing(event_tlast_missing),                  // output wire event_tlast_missing
  .event_status_channel_halt(event_status_channel_halt),      // output wire event_status_channel_halt
  .event_data_in_channel_halt(event_data_in_channel_halt),    // output wire event_data_in_channel_halt
  .event_data_out_channel_halt(event_data_out_channel_halt)  // output wire event_data_out_channel_halt
);

reg [7:0] num_sample;
initial begin 
    phase_correction <= 0;
    next_phase_correction <= 0;
end

// integer i;
integer j;
always @(posedge clock) begin
    if (reset) begin
        for (j = 0; j < 32; j= j+1) begin
            cross_corr_buf[j] <= 0;
        end
        do_clear();
        state <= S_SKIPPING_TAIL;
        reset_delay1 <= reset;
        reset_delay2 <= reset;
        reset_delay3 <= reset;
        reset_delay4 <= reset;
        ltf_phase_offset_int <= 0;
        phase_out_neg <= 0;
        phase_offset_neg <= 0;
        fft_din_data_tlast <= 1'b0;
        sample_delayed_conj_stb <= sample_delayed_stb;
        sample_delayed_conj[31:16] <= sample_delayed[31:16];
        sample_delayed_conj[15:0] <= ~sample_delayed[15:0]+1; 
    end else if (enable) begin
        reset_delay4 <= reset_delay3;
        reset_delay3 <= reset_delay2;
        reset_delay2 <= reset_delay1;
        reset_delay1 <= reset;
        sample_delayed_conj_stb <= sample_delayed_stb;
        sample_delayed_conj[31:16] <= sample_delayed[31:16];
        sample_delayed_conj[15:0] <= ~sample_delayed[15:0]+1;   
        phase_out_neg <= ~phase_out + 1;
        phase_offset_neg <= {{6{phase_out[15]}}, phase_out[15:6]};
        if (sample_in_strobe && state != S_SKIPPING_TAIL) begin
            in_waddr <= in_waddr + 1;
            num_input_produced <= num_input_produced + 1;
        end
        num_input_avail <= num_input_produced - num_input_consumed;

        case(state)
            S_SKIPPING_TAIL: begin
                // skip the tail of  short preamble
                if (num_sample >= NUM_STS_TAIL) begin
                    //num_sample <= 0;
                    state <= S_SKIPPING_CP;
                end else if (sample_in_strobe) begin
                    num_sample <= num_sample + 1;
                end
            end
            S_SKIPPING_CP: begin
                // skip the tail of  short preamble
                if (num_sample >= NUM_STS_TAIL + NUM_ADD_SP_TO_SKIP) begin
                    num_sample <= 0;
                    state <= S_WAIT_FOR_FIRST_PEAK;
                end else if (sample_in_strobe) begin
                    num_sample <= num_sample + 1;
                end
            end
            S_WAIT_FOR_FIRST_PEAK: begin
                do_mult();

                if (metric_stb && (metric > metric_max1) && (num_sample <= 62)) begin
                    metric_max1 <= metric;
                    addr1 <= in_raddr - 1 -fft_win_shift;
                end

                if (num_sample >= 63) begin
                    // offset it by the length of cross correlation buffer
                    // size
                    //in_raddr <= addr1 - 32;
                    //num_input_consumed <= addr1 - 32;
                    in_offset <= 0;
                    num_ofdm_symbol <= 0;
                    state <= S_WAIT_FOR_SECOND_PEAK;
                end 
                if (metric_stb) begin
                    num_sample <= num_sample + 1;
                end

            end
            
            S_WAIT_FOR_SECOND_PEAK: begin
                do_mult();

                if (num_sample >= 64 + addr1 + 8 + fft_win_shift + 3 - NUM_ADD_SP_TO_SKIP && phase_out_stb == 1) begin // 64 + addr1
                    num_sample <= 0;
                    mult_strobe <= 0;
                    sum_stb <= 0;
                    if(phase_out_neg[5] == 0)  // E.g. 131/16 = 8.1875 -> 8, -138/16 = -8.625 -> -9
                        ltf_phase_offset_int <= {{6{phase_out_neg[15]}}, phase_out_neg[15:6]};
                    else  // E.g. -131/16 = -8.1875 -> -8, 138/16 = 8.625 -> 9
                        ltf_phase_offset_int <= ~phase_offset_neg + 1;
                    state <= S_FFT;
                    long_preamble_detected <= 1;
                    in_raddr <= (addr1+NUM_ADD_SP_TO_SKIP) - 32;
                    num_input_consumed <= (addr1+NUM_ADD_SP_TO_SKIP) - 32;
                end else if (metric_stb) begin
                    num_sample <= num_sample + 1;
                end

            end 

            S_FFT: begin
                if (long_preamble_detected) begin
                    `ifdef DEBUG_PRINT
                        $display("Long preamble detected");
                    `endif
                    long_preamble_detected <= 0;
                    phase_correction <= 0;
                    next_phase_correction <= ltf_phase_offset;
                end

                if (~fft_loading && num_input_avail > 88) begin
                    fft_start <= 1;
                    in_offset <= 0;
                end

                if (fft_start) begin
                    fft_start <= 0;
                    fft_loading <= 1;
                end

                raw_stb <= fft_start | fft_loading;
                if (raw_stb) begin
                    if (ltf_phase_offset > 0) begin
                        if (next_phase_correction > PI) begin
                            phase_correction <= next_phase_correction - DOUBLE_PI;
                            if(in_offset == 63 && num_ofdm_symbol > 0)
                                next_phase_correction <= next_phase_correction - DOUBLE_PI + ltf_phase_offset + (short_gi ? ltf_phase_offset<<<3 : ltf_phase_offset<<<4);
                            else
                                next_phase_correction <= next_phase_correction - DOUBLE_PI + ltf_phase_offset;
                        end else begin
                            phase_correction <= next_phase_correction;
                            if(in_offset == 63 && num_ofdm_symbol > 0)
                                next_phase_correction <= next_phase_correction + ltf_phase_offset + (short_gi ? ltf_phase_offset<<<3 : ltf_phase_offset<<<4);
                            else
                                next_phase_correction <= next_phase_correction + ltf_phase_offset;
                        end
                    end else begin
                        if (next_phase_correction < -PI) begin
                            phase_correction <= next_phase_correction + DOUBLE_PI;
                            if(in_offset == 63 && num_ofdm_symbol > 0)
                                next_phase_correction <= next_phase_correction + DOUBLE_PI + ltf_phase_offset + (short_gi ? ltf_phase_offset<<<3 : ltf_phase_offset<<<4);
                            else
                                next_phase_correction <= next_phase_correction + DOUBLE_PI + ltf_phase_offset;
                        end else begin
                            phase_correction <= next_phase_correction;
                            if(in_offset == 63 && num_ofdm_symbol > 0)
                                next_phase_correction <= next_phase_correction + ltf_phase_offset + (short_gi ? ltf_phase_offset<<<3 : ltf_phase_offset<<<4);
                            else
                                next_phase_correction <= next_phase_correction + ltf_phase_offset;
                        end
                    end
                end

                if (fft_start | fft_loading) begin
                    in_offset <= in_offset + 1;
                    
                    if( in_offset == 62) begin
                        fft_din_data_tlast <= 1'b1;
                    end

                    if (in_offset == 63) begin
                        fft_din_data_tlast <= 1'b0;
                        fft_loading <= 0;
                        num_ofdm_symbol <= (num_ofdm_symbol == 32767? num_ofdm_symbol : (num_ofdm_symbol + 1)); // normally should not run into saturation!
                        if (num_ofdm_symbol > 0) begin
                            // skip the Guard Interval for data symbols
                            in_raddr <= in_raddr + gi_skip;
                            num_input_consumed <= num_input_consumed + gi_skip;
                        end else begin
                            in_raddr <= in_raddr + 1;
                            num_input_consumed <= num_input_consumed + 1;
                        end
                    end else begin
                        in_raddr <= in_raddr + 1;
                        num_input_consumed <= num_input_consumed + 1;
                    end
                end

                sample_out_strobe <= fft_valid;
                sample_out <= fft_out;
            end

            S_IDLE: begin
            end

            default: begin
                state <= S_WAIT_FOR_FIRST_PEAK;
            end
        endcase
    end else begin
        sample_out_strobe <= 0;
    end
end

integer do_mult_i;
task do_mult; begin
    // cross correlation of the first 16 samples of LTS
    if (sample_in_strobe) begin
        cross_corr_buf[31] <= sample_in;
        for (do_mult_i = 0; do_mult_i < 31; do_mult_i = do_mult_i+1) begin
            cross_corr_buf[do_mult_i] <= cross_corr_buf[do_mult_i+1];
        end

        sum_stage <= 0;
        sum_i <= 0;
        sum_q <= 0;
        sum_stb <= 0;

        stage_X0 <= cross_corr_buf[1];
        stage_X1 <= cross_corr_buf[2];
        stage_X2 <= cross_corr_buf[3];
        stage_X3 <= cross_corr_buf[4];
        stage_X4 <= cross_corr_buf[5];
        stage_X5 <= cross_corr_buf[6];
        stage_X6 <= cross_corr_buf[7];
        stage_X7 <= cross_corr_buf[8];

        stage_Y0 <= { 16'd156, 16'd0};
        stage_Y1 <= {-16'd5,   16'd120};
        stage_Y2 <= { 16'd40,  16'd111};
        stage_Y3 <= { 16'd97, -16'd83};
        stage_Y4 <= { 16'd21, -16'd28};
        stage_Y5 <= { 16'd60,  16'd88};
        stage_Y6 <= {-16'd115, 16'd55};
        stage_Y7 <= {-16'd38,  16'd106};

        mult_strobe <= 1;
        mult_stage <= 1;
    end

    if (mult_stage == 1) begin
        stage_X0 <= cross_corr_buf[8];
        stage_X1 <= cross_corr_buf[9];
        stage_X2 <= cross_corr_buf[10];
        stage_X3 <= cross_corr_buf[11];
        stage_X4 <= cross_corr_buf[12];
        stage_X5 <= cross_corr_buf[13];
        stage_X6 <= cross_corr_buf[14];
        stage_X7 <= cross_corr_buf[15];

        stage_Y0 <= { 16'd98,  16'd26};
        stage_Y1 <= { 16'd53, -16'd4};
        stage_Y2 <= { 16'd1,   16'd115};
        stage_Y3 <= {-16'd137, 16'd47};
        stage_Y4 <= { 16'd24,  16'd59};
        stage_Y5 <= { 16'd59,  16'd15};
        stage_Y6 <= {-16'd22, -16'd161};
        stage_Y7 <= { 16'd119, 16'd4};

        mult_stage <= 2;
    end else if (mult_stage == 2) begin
        stage_X0 <= cross_corr_buf[16];
        stage_X1 <= cross_corr_buf[17];
        stage_X2 <= cross_corr_buf[18];
        stage_X3 <= cross_corr_buf[19];
        stage_X4 <= cross_corr_buf[20];
        stage_X5 <= cross_corr_buf[21];
        stage_X6 <= cross_corr_buf[22];
        stage_X7 <= cross_corr_buf[23];

        stage_Y0 <= { 16'd62,    16'd62};
        stage_Y1 <= { 16'd37,  -16'd98};
        stage_Y2 <= {-16'd57,  -16'd39};
        stage_Y3 <= {-16'd131, -16'd65};
        stage_Y4 <= { 16'd82,  -16'd92};
        stage_Y5 <= { 16'd70,  -16'd14};
        stage_Y6 <= {-16'd60,  -16'd81};
        stage_Y7 <= {-16'd56,   16'd22};

        mult_stage <= 3;
    end else if (mult_stage == 3) begin
        stage_X0 <= cross_corr_buf[24];
        stage_X1 <= cross_corr_buf[25];
        stage_X2 <= cross_corr_buf[26];
        stage_X3 <= cross_corr_buf[27];
        stage_X4 <= cross_corr_buf[28];
        stage_X5 <= cross_corr_buf[29];
        stage_X6 <= cross_corr_buf[30];
        stage_X7 <= cross_corr_buf[31];

        stage_Y0 <= {-16'd35,  16'd151};
        stage_Y1 <= {-16'd122, 16'd17};
        stage_Y2 <= {-16'd127, 16'd21};
        stage_Y3 <= { 16'd75,  16'd74};
        stage_Y4 <= {-16'd3,  -16'd54};
        stage_Y5 <= {-16'd92, -16'd115};
        stage_Y6 <= { 16'd92, -16'd106};
        stage_Y7 <= { 16'd12, -16'd98};

        mult_stage <= 4;
    end else if (mult_stage == 4) begin
        mult_stage <= 0;
        mult_strobe <= 0;
        in_raddr <= in_raddr + 1;
        num_input_consumed <= num_input_consumed + 1;
    end

    if (stage_sum_stb) begin
        sum_stage <= sum_stage + 1;
        sum_i <= sum_i + stage_sum_i;
        sum_q <= sum_q + stage_sum_q;
        if (sum_stage == 3) begin
            sum_stb <= 1;
        end
    end else begin
        sum_stb <= 0;
        sum_i <= 0;
        sum_q <= 0;
    end
end
endtask

task do_clear; begin

    in_waddr <= 0;
    in_raddr <= 0;
    in_offset <= 0;
    num_input_produced <= 0;
    num_input_consumed <= 0;
    num_input_avail <= 0;

    phase_correction <= 0;
    next_phase_correction <= 0;

    raw_stb <= 0;

    sum_i <= 0;
    sum_q <= 0;
    sum_stb <= 0;
    sum_stage <= 0;
    mult_strobe <= 0;

    metric_max1 <= 0;
    addr1 <= 0;

    mult_stage <= 0;

    long_preamble_detected <= 0;
    num_sample <= 0;
    num_ofdm_symbol <= 0;

    fft_start <= 0;
    fft_loading <= 0;

    sample_out_strobe <= 0;
    sample_out <= 0;

    stage_X0 <= 0;
    stage_X1 <= 0;
    stage_X2 <= 0;
    stage_X3 <= 0;
    stage_X4 <= 0;
    stage_X5 <= 0;
    stage_X6 <= 0;
    stage_X7 <= 0;

    stage_Y0 <= 0;
    stage_Y1 <= 0;
    stage_Y2 <= 0;
    stage_Y3 <= 0;
    stage_Y4 <= 0;
    stage_Y5 <= 0;
    stage_Y6 <= 0;
    stage_Y7 <= 0;
end
endtask

endmodule
