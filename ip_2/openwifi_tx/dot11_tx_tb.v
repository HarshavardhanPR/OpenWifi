`timescale 1ns/1ps

module dot11_tx_tb;

  // ------------------------------------------------------------
  // Parameters and Local Constants
  // ------------------------------------------------------------
  localparam BRAM_DEPTH = 1024;
  localparam VERBOSE_LOGGING = 1;

  // ------------------------------------------------------------
  // Inputs to DUT
  // ------------------------------------------------------------
  reg           clk = 0;
  reg           phy_tx_arest;
  reg           phy_tx_start;
  reg  [6:0]    init_pilot_scram_state;
  reg  [6:0]    init_data_scram_state;
  reg  [63:0]   bram_din;
  reg           result_iq_ready; // This will now be driven high

  // ------------------------------------------------------------
  // Outputs from DUT
  // ------------------------------------------------------------
  wire          phy_tx_done;
  wire          phy_tx_started;
  wire [9:0]    bram_addr;
  wire          result_iq_valid;
  wire [15:0]   result_i;
  wire [15:0]   result_q;

  // ------------------------------------------------------------
  // DUT Instantiation
  // ------------------------------------------------------------
  dot11_tx dut (
    .clk(clk),
    .phy_tx_arest(phy_tx_arest),
    .phy_tx_start(phy_tx_start),
    .phy_tx_done(phy_tx_done),
    .phy_tx_started(phy_tx_started),
    .init_pilot_scram_state(init_pilot_scram_state),
    .init_data_scram_state(init_data_scram_state),
    .bram_din(bram_din),
    .bram_addr(bram_addr),
    .result_iq_ready(result_iq_ready),
    .result_iq_valid(result_iq_valid),
    .result_i(result_i),
    .result_q(result_q)
  );

  // ------------------------------------------------------------
  // Clock Generation (50 MHz)
  // ------------------------------------------------------------
  always #10 clk = ~clk;

  // ------------------------------------------------------------
  // Simulated BRAM
  // ------------------------------------------------------------
  reg [63:0] bram_memory [0:BRAM_DEPTH-1];
  always @(posedge clk)
    bram_din <= bram_memory[bram_addr];

  // ------------------------------------------------------------
  // Packet Loader Task
  // ------------------------------------------------------------
  task load_bram_packet;
    input reg PKT_TYPE_IN;
    input [3:0] RATE_FIELD_IN;
    input [15:0] PSDU_LEN_BYTES_IN;
    reg [63:0] plcp_word0, plcp_word1;
    reg [10:0] psdu_len_for_l_sig;
    reg [13:0] psdu_len_for_ht_sig;
    integer i;
    begin
      $display("Loading Packet: Type=%s, Rate/MCS=%0d, Length=%0d bytes",
               PKT_TYPE_IN ? "HT" : "LEGACY", RATE_FIELD_IN, PSDU_LEN_BYTES_IN);

      // Clear BRAM
      for (i = 0; i < BRAM_DEPTH; i = i + 1)
        bram_memory[i] = 64'h0;

      if (!PKT_TYPE_IN) begin
        // LEGACY
        psdu_len_for_l_sig = PSDU_LEN_BYTES_IN;
        plcp_word0 = {47'h0, PKT_TYPE_IN, psdu_len_for_l_sig, 5'h0, RATE_FIELD_IN};
        bram_memory[0] = plcp_word0;
      end else begin
        // HT
        plcp_word0 = {47'h0, 1'b1, 11'd0, 5'h0, 4'b1011}; // L_SIG (rate = 6Mbps)
        bram_memory[0] = plcp_word0;
        psdu_len_for_ht_sig = PSDU_LEN_BYTES_IN;
        plcp_word1 = {32'h0, 1'b0, 1'b0, psdu_len_for_ht_sig, 10'h0, RATE_FIELD_IN, 13'h0};
        bram_memory[1] = plcp_word1;
      end

      for (i = 2; i < (2 + PSDU_LEN_BYTES_IN / 8 + (PSDU_LEN_BYTES_IN % 8 > 0)); i = i + 1)
        bram_memory[i] = {63'h0, i[0]}; // simple pattern
    end
  endtask

  // ------------------------------------------------------------
  // Initial Block (Main Test Control)
  // ------------------------------------------------------------
  integer iq_log_file;
  integer i; // This 'i' is local to the initial block, not the 'i' that was X
  initial begin
    // Initialize
    phy_tx_arest = 1;
    phy_tx_start = 0;
    result_iq_ready = 1; // <--- MODIFIED: Keep result_iq_ready high
    init_pilot_scram_state = 7'b1010101;
    init_data_scram_state  = 7'b1100110;
    bram_din = 0;

    iq_log_file = $fopen("dot11_tx_iq.txt", "w");
    if (!iq_log_file) begin
      $error("Could not open dot11_tx_iq.txt!");
      $finish;
    end

    $display("=== Beginning Simulation ===");

    // Reset
    #40 phy_tx_arest = 0;
    $display("Reset Deasserted at %0t", $time);

    // --- Test Case 1: Legacy Packet ---
    $display("\n[TEST CASE 1] LEGACY Packet: 12Mbps, 200 bytes");
    load_bram_packet(0, 4'b1010, 200);
    #40 phy_tx_start = 1;
    #20 phy_tx_start = 0;

    wait (phy_tx_started);
    $display("phy_tx_started asserted at %0t", $time);
    wait (phy_tx_done);
    $display("phy_tx_done asserted at %0t", $time);
    #40;

    // Reset before next test
    phy_tx_arest = 1; #40; phy_tx_arest = 0;

    // --- Test Case 2: HT Packet ---
    $display("\n[TEST CASE 2] HT Packet: MCS 3, 300 bytes");
    load_bram_packet(1, 4'b0011, 300);
    #40 phy_tx_start = 1;
    #20 phy_tx_start = 0;

    wait (phy_tx_started);
    $display("phy_tx_started asserted at %0t", $time);
    wait (phy_tx_done);
    $display("phy_tx_done asserted at %0t", $time);
    #40;

    $display("\n=== Simulation Complete ===");
    $fclose(iq_log_file);
    $finish;
  end

  // ------------------------------------------------------------
  // Handshake + IQ Logging
  // ------------------------------------------------------------
  // This block is now primarily for logging, as result_iq_ready is externally driven high.
  // The logic for result_iq_ready <= result_iq_valid; is no longer strictly necessary
  // if result_iq_ready is always 1, but keeping it doesn't hurt.
  // The logging condition is now simplified to just result_iq_valid.
  always @(posedge clk) begin
    if (phy_tx_arest) begin
      // result_iq_ready <= 0; // No need to drive this from here if it's tied high in initial
    end else begin
      // result_iq_ready <= result_iq_valid; // No longer needed if tied high.
                                           // If you want to simulate a *real* handshake,
                                           // you'd need more complex logic here.
      if (result_iq_valid) begin // Log when the DUT asserts valid
        $fwrite(iq_log_file, "%0t, %0d, %0d\n", $time, result_i, result_q);
        if (VERBOSE_LOGGING)
          $display("IQ @ %0t => I: %0d, Q: %0d", $time, result_i, result_q);
      end
    end
  end

  // ------------------------------------------------------------
  // Timeout Catcher
  // ------------------------------------------------------------
  initial begin
    #2_000_000;
    $error("Simulation timeout! phy_tx_done not detected.");
    $finish;
  end

endmodule