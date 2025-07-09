module stage_mult (
    input clock,
    input enable,
    input reset,

    input signed [31:0] X0, X1, X2, X3, X4, X5, X6, X7,
    input signed [31:0] Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7,
    input input_strobe,

    output reg [63:0] sum,
    output output_strobe
);

// Split complex inputs into real (i) and imaginary (q) parts
wire signed [15:0] X0_q = X0[31:16]; wire signed [15:0] X0_i = X0[15:0];
wire signed [15:0] X1_q = X1[31:16]; wire signed [15:0] X1_i = X1[15:0];
wire signed [15:0] X2_q = X2[31:16]; wire signed [15:0] X2_i = X2[15:0];
wire signed [15:0] X3_q = X3[31:16]; wire signed [15:0] X3_i = X3[15:0];
wire signed [15:0] X4_q = X4[31:16]; wire signed [15:0] X4_i = X4[15:0];
wire signed [15:0] X5_q = X5[31:16]; wire signed [15:0] X5_i = X5[15:0];
wire signed [15:0] X6_q = X6[31:16]; wire signed [15:0] X6_i = X6[15:0];
wire signed [15:0] X7_q = X7[31:16]; wire signed [15:0] X7_i = X7[15:0];

wire signed [15:0] Y0_q = Y0[31:16]; wire signed [15:0] Y0_i = Y0[15:0];
wire signed [15:0] Y1_q = Y1[31:16]; wire signed [15:0] Y1_i = Y1[15:0];
wire signed [15:0] Y2_q = Y2[31:16]; wire signed [15:0] Y2_i = Y2[15:0];
wire signed [15:0] Y3_q = Y3[31:16]; wire signed [15:0] Y3_i = Y3[15:0];
wire signed [15:0] Y4_q = Y4[31:16]; wire signed [15:0] Y4_i = Y4[15:0];
wire signed [15:0] Y5_q = Y5[31:16]; wire signed [15:0] Y5_i = Y5[15:0];
wire signed [15:0] Y6_q = Y6[31:16]; wire signed [15:0] Y6_i = Y6[15:0];
wire signed [15:0] Y7_q = Y7[31:16]; wire signed [15:0] Y7_i = Y7[15:0];

// Product outputs
wire signed [31:0] prod_0_i, prod_0_q;
wire signed [31:0] prod_1_i, prod_1_q;
wire signed [31:0] prod_2_i, prod_2_q;
wire signed [31:0] prod_3_i, prod_3_q;
wire signed [31:0] prod_4_i, prod_4_q;
wire signed [31:0] prod_5_i, prod_5_q;
wire signed [31:0] prod_6_i, prod_6_q;
wire signed [31:0] prod_7_i, prod_7_q;

// Instantiate the flat-port complex_multiplier 8 times
complex_multiplier mult_inst1 (.clk(clock), .ar(X0_i), .ai(X0_q), .br(Y0_i), .bi(Y0_q), .pi(prod_0_i), .pr(prod_0_q));
complex_multiplier mult_inst2 (.clk(clock), .ar(X1_i), .ai(X1_q), .br(Y1_i), .bi(Y1_q), .pi(prod_1_i), .pr(prod_1_q));
complex_multiplier mult_inst3 (.clk(clock), .ar(X2_i), .ai(X2_q), .br(Y2_i), .bi(Y2_q), .pi(prod_2_i), .pr(prod_2_q));
complex_multiplier mult_inst4 (.clk(clock), .ar(X3_i), .ai(X3_q), .br(Y3_i), .bi(Y3_q), .pi(prod_3_i), .pr(prod_3_q));
complex_multiplier mult_inst5 (.clk(clock), .ar(X4_i), .ai(X4_q), .br(Y4_i), .bi(Y4_q), .pi(prod_4_i), .pr(prod_4_q));
complex_multiplier mult_inst6 (.clk(clock), .ar(X5_i), .ai(X5_q), .br(Y5_i), .bi(Y5_q), .pi(prod_5_i), .pr(prod_5_q));
complex_multiplier mult_inst7 (.clk(clock), .ar(X6_i), .ai(X6_q), .br(Y6_i), .bi(Y6_q), .pi(prod_6_i), .pr(prod_6_q));
complex_multiplier mult_inst8 (.clk(clock), .ar(X7_i), .ai(X7_q), .br(Y7_i), .bi(Y7_q), .pi(prod_7_i), .pr(prod_7_q));

// Intermediate sums
reg signed [31:0] sum_i1, sum_i2, sum_i3, sum_i4;
reg signed [31:0] sum_q1, sum_q2, sum_q3, sum_q4;

// Delay input_strobe to sync output
delayT #(.DATA_WIDTH(1), .DELAY(5)) sum_delay_inst (
    .clock(clock),
    .reset(reset),
    .data_in(input_strobe),
    .data_out(output_strobe)
);

// Accumulate final outputs
always @(posedge clock) begin
    if (reset) begin
        sum <= 0;
        sum_i1 <= 0; sum_i2 <= 0; sum_i3 <= 0; sum_i4 <= 0;
        sum_q1 <= 0; sum_q2 <= 0; sum_q3 <= 0; sum_q4 <= 0;
    end else if (enable) begin
        sum_i1 <= prod_0_i + prod_1_i;
        sum_i2 <= prod_2_i + prod_3_i;
        sum_i3 <= prod_4_i + prod_5_i;
        sum_i4 <= prod_6_i + prod_7_i;

        sum_q1 <= prod_0_q + prod_1_q;
        sum_q2 <= prod_2_q + prod_3_q;
        sum_q3 <= prod_4_q + prod_5_q;
        sum_q4 <= prod_6_q + prod_7_q;

        sum[63:32] <= sum_i1 + sum_i2 + sum_i3 + sum_i4;
        sum[31:0]  <= sum_q1 + sum_q2 + sum_q3 + sum_q4;
    end
end

endmodule
