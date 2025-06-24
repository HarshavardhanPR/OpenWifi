// Xianjun jiao. putaoshu@msn.com; xianjun.jiao@imec.be;
//`include "openofdm_rx_pre_def.v"

`ifdef OPENOFDM_RX_ENABLE_DBG
`define DEBUG_PREFIX (*mark_debug="true",DONT_TOUCH="TRUE"*)
`else
`define DEBUG_PREFIX
`endif

module signal_watchdog
#(
    parameter integer IQ_DATA_WIDTH	= 16,
    parameter LOG2_SUM_LEN = 6
)
(
    input clk,
    input rstn,
    input enable,

    input signed [(IQ_DATA_WIDTH-1):0] i_data,
    input signed [(IQ_DATA_WIDTH-1):0] q_data,
    input iq_valid,

    input power_trigger,

    input [15:0] signal_len,
    input sig_valid,

    input [15:0] min_signal_len_th,
    input [15:0] max_signal_len_th,
    input signed [(LOG2_SUM_LEN+2-1):0] dc_running_sum_th,

    // equalizer monitor: the normalized constellation shoud not be too small (like only has 1 or 2 bits effective)
    input wire equalizer_monitor_enable,
    input wire [5:0] small_eq_out_counter_th,
    `DEBUG_PREFIX input wire [4:0] state,
		`DEBUG_PREFIX input wire [31:0] equalizer,
		`DEBUG_PREFIX input wire equalizer_valid,

    `DEBUG_PREFIX output receiver_rst
);
`include "common_params.v"

    wire signed [1:0] i_sign;
    wire signed [1:0] q_sign;
    reg  signed [1:0] fake_non_dc_in_case_all_zero;
    wire signed [(LOG2_SUM_LEN+2-1):0] running_sum_result_i;
    wire signed [(LOG2_SUM_LEN+2-1):0] running_sum_result_q;
    `DEBUG_PREFIX wire signed [(LOG2_SUM_LEN+2-1):0] running_sum_result_i_abs;
    `DEBUG_PREFIX wire signed [(LOG2_SUM_LEN+2-1):0] running_sum_result_q_abs;

    `DEBUG_PREFIX wire receiver_rst_internal;
    `DEBUG_PREFIX reg receiver_rst_reg;
    `DEBUG_PREFIX wire receiver_rst_pulse;

    `DEBUG_PREFIX wire equalizer_monitor_enable_internal;
    `DEBUG_PREFIX wire [15:0] eq_out_i;
    `DEBUG_PREFIX wire [15:0] eq_out_q;
    `DEBUG_PREFIX reg [15:0] abs_eq_i;
    `DEBUG_PREFIX reg [15:0] abs_eq_q;
    `DEBUG_PREFIX reg [5:0] small_abs_eq_i_counter;
    `DEBUG_PREFIX reg [5:0] small_abs_eq_q_counter;
    `DEBUG_PREFIX wire equalizer_monitor_rst;

    assign i_sign = (i_data == 0? fake_non_dc_in_case_all_zero : (i_data[(IQ_DATA_WIDTH-1)] ? -1 : 1) );
    assign q_sign = (q_data == 0? fake_non_dc_in_case_all_zero : (q_data[(IQ_DATA_WIDTH-1)] ? -1 : 1) );

    assign running_sum_result_i_abs = (running_sum_result_i[LOG2_SUM_LEN+2-1]?(-running_sum_result_i):running_sum_result_i);
    assign running_sum_result_q_abs = (running_sum_result_q[LOG2_SUM_LEN+2-1]?(-running_sum_result_q):running_sum_result_q);

    assign receiver_rst_internal = (enable&(running_sum_result_i_abs>=dc_running_sum_th || running_sum_result_q_abs>=dc_running_sum_th));

    assign receiver_rst_pulse = (receiver_rst_internal&&(~receiver_rst_reg));

    assign equalizer_monitor_enable_internal = (equalizer_monitor_enable && (state == S_DECODE_SIGNAL));
    assign eq_out_i = equalizer[31:16];
    assign eq_out_q = equalizer[15:0];

    assign equalizer_monitor_rst = ( (small_abs_eq_i_counter>=small_eq_out_counter_th) && (small_abs_eq_q_counter>=small_eq_out_counter_th) );

    assign receiver_rst = ( power_trigger & ( equalizer_monitor_rst | receiver_rst_reg | (sig_valid && (signal_len<min_signal_len_th || signal_len>max_signal_len_th)) ) );

    // abnormal signal monitor
    always @(posedge clk) begin
      if (~rstn) begin
        receiver_rst_reg <= 0;
        fake_non_dc_in_case_all_zero <= 1;
      end else begin
        receiver_rst_reg <= receiver_rst_internal;
        if (iq_valid) begin
          if (fake_non_dc_in_case_all_zero == 1) begin
            fake_non_dc_in_case_all_zero <= -1;
          end else begin
            fake_non_dc_in_case_all_zero <= 1;
          end
        end
      end
    end

    running_sum_dual_ch #(.DATA_WIDTH0(2), .DATA_WIDTH1(2), .LOG2_SUM_LEN(LOG2_SUM_LEN)) signal_watchdog_running_sum_inst (
      .clk(clk),
      .rstn(rstn),

      .data_in0(i_sign),
      .data_in1(q_sign),
      .data_in_valid(iq_valid),
      .running_sum_result0(running_sum_result_i),
      .running_sum_result1(running_sum_result_q),
      .data_out_valid()
    );

    // equalizer monitor
    always @(posedge clk) begin
      if (~equalizer_monitor_enable_internal) begin
        small_abs_eq_i_counter <= 0;
        small_abs_eq_q_counter <= 0;
        abs_eq_i <= 0;
        abs_eq_q <= 0;
      end else begin
        if (equalizer_valid) begin
          abs_eq_i <= eq_out_i[15]? ~eq_out_i+1: eq_out_i;
          abs_eq_q <= eq_out_q[15]? ~eq_out_q+1: eq_out_q;
          small_abs_eq_i_counter <= (abs_eq_i<=2?(small_abs_eq_i_counter+1):small_abs_eq_i_counter);
          small_abs_eq_q_counter <= (abs_eq_q<=2?(small_abs_eq_q_counter+1):small_abs_eq_q_counter);
        end
      end
    end

endmodule
