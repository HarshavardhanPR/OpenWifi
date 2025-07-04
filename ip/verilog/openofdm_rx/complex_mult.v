module complex_mult
(
    input clock,
    input enable,
    input reset,

    input [15:0] a_i,
    input [15:0] a_q,
    input [15:0] b_i,
    input [15:0] b_q,
    input input_strobe,

    output [31:0] p_i,
    output [31:0] p_q,
    output output_strobe
);

wire [63:0] m_axis_dout_tdata;
assign p_q = m_axis_dout_tdata[63:32];
assign p_i = m_axis_dout_tdata[31:0];
/*complex_multiplier mult_inst (
  .aclk(clock),                                 // input wire aclk
  .s_axis_a_tvalid(input_strobe),        	// input wire s_axis_a_tvalid
  .s_axis_a_tdata({a_q, a_i}),         	// input wire [31 : 0] s_axis_a_tdata
  .s_axis_b_tvalid(input_strobe),        	// input wire s_axis_b_tvalid
  .s_axis_b_tdata({b_q, b_i}),          	// input wire [31 : 0] s_axis_b_tdata
  .m_axis_dout_tvalid(output_strobe),  	// output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(m_axis_dout_tdata)    	// output wire [63 : 0] m_axis_dout_tdata
);*/

complex_multiplier mult_inst (
    .clk(clock),
    .ar(a_i),
    .ai(a_q),
    .br(b_i),
    .bi(b_q),
    .pi(p_i),
    .pr(p_q)
);



// reg [15:0] ar;
// reg [15:0] ai;
// reg [15:0] br;
// reg [15:0] bi;

// wire [31:0] prod_i;
// wire [31:0] prod_q;

// // instantiation of complex multiplier
// wire [31:0] s_axis_a_tdata;
// assign s_axis_a_tdata = {ai,ar} ;
// wire [31:0] s_axis_b_tdata;
// assign s_axis_b_tdata = {bi, br} ;
// wire [63:0] m_axis_dout_tdata;
// assign prod_q = m_axis_dout_tdata[63:32];
// assign prod_i = m_axis_dout_tdata[31:0];
// wire m_axis_dout_tvalid ;

// assign output_strobe = m_axis_dout_tvalid; //output strobe valid at the beginning of new data -- simulation confirmed

// complex_multiplier mult_inst (
//   .aclk(clock),                                 // input wire aclk
//   .s_axis_a_tvalid(input_strobe),        	// input wire s_axis_a_tvalid
//   .s_axis_a_tdata(s_axis_a_tdata),         	// input wire [31 : 0] s_axis_a_tdata
//   .s_axis_b_tvalid(input_strobe),        	// input wire s_axis_b_tvalid
//   .s_axis_b_tdata(s_axis_b_tdata),          	// input wire [31 : 0] s_axis_b_tdata
//   .m_axis_dout_tvalid(m_axis_dout_tvalid),  	// output wire m_axis_dout_tvalid
//   .m_axis_dout_tdata(m_axis_dout_tdata)    	// output wire [63 : 0] m_axis_dout_tdata
// );

// always @(posedge clock) begin
//     if (reset) begin
//         ar <= 0;
//         ai <= 0;
//         br <= 0;
//         bi <= 0;
//         p_i <= 0;
//         p_q <= 0;
//     end else if (enable) begin
//         ar <= a_i;
//         ai <= a_q;
//         br <= b_i;
//         bi <= b_q;

//         p_i <= prod_i;
//         p_q <= prod_q;
//     end
// end

endmodule
