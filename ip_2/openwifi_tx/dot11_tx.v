`timescale 1ns/1ps

module dot11_tx
(
  input  wire          clk,
  input  wire          phy_tx_arest,

  input  wire          phy_tx_start,
  output reg           phy_tx_done,
  output reg           phy_tx_started,

  input  wire [6:0]    init_pilot_scram_state,
  input  wire [6:0]    init_data_scram_state,

  input  wire [63:0]   bram_din,
  output reg  [9:0]    bram_addr,

  input  wire          result_iq_ready,
  output wire          result_iq_valid,
  output wire [15:0]  result_i,
  output wire [15:0]  result_q
);

reg  FSM3_reset;         // Reset after transmitting a whole packet
wire reset_int = phy_tx_arest | FSM3_reset; // Combined reset signal

// Data collection states (FSM1)
reg [1:0] state1;
localparam S1_WAIT_PKT = 2'd0;
localparam S1_L_SIG    = 2'd1;
localparam S1_HT_SIG   = 2'd2;
localparam S1_DATA     = 2'd3;

reg [2:0] state11; // Sub-state for S1_DATA
localparam S11_SERVICE   = 3'd0;
localparam S11_PSDU_DATA = 3'd1;
localparam S11_PSDU_CRC  = 3'd2;
localparam S11_TAIL      = 3'd3;
localparam S11_PAD       = 3'd4;
localparam S11_RESET     = 3'd5; // Added an explicit reset state to FSM11

// IQ sample generation states (FSM2)
reg [1:0] state2;
localparam S2_PUNC_INTERLV   = 2'd0;
localparam S2_PILOT_DC_SB    = 2'd1;
localparam S2_MOD_IFFT_INPUT = 2'd2;
localparam S2_RESET          = 2'd3;

// IQ sample forwarding states (FSM3)
reg [2:0] state3;
localparam S3_WAIT_PKT = 3'd0;
localparam S3_L_STF    = 3'd1;
localparam S3_L_LTF    = 3'd2;
localparam S3_L_SIG    = 3'd3;
localparam S3_HT_SIG   = 3'd4;
localparam S3_HT_STF   = 3'd5;
localparam S3_HT_LTF   = 3'd6;
localparam S3_DATA     = 3'd7; // 3'd7 means 8 states, max for 3 bits is 3'b111 (7)

// Packet Type
reg PKT_TYPE;
localparam LEGACY = 1'b0;
localparam HT     = 1'b1;

// Output status
localparam NO_OUTPUT_YET  = 1'b0;
localparam OUTPUT_STARTED = 1'b1;

// FIFO Turn (for IQ sample selection)
localparam CP_FIFO  = 1'b0;
localparam PKT_FIFO = 1'b1;

// Counters and Registers for FSM1
reg [5:0]  plcp_bit_cnt;
reg [3:0]  service_bit_cnt;
reg [18:0] psdu_bit_cnt;         // Maximum number of PSDU bits = 65536*8 = 524288
reg [14:0] ofdm_cnt_FSM1;        // Maximum number of OFDM symbols = 3 + ceil((16+524288+6)/26) = 20169

//////////////////////////////////////////////////////////////////////////
// LEGACY SHORT + LONG PREAMBLE ROMs
//////////////////////////////////////////////////////////////////////////
wire [31:0] l_stf;
wire [31:0] l_ltf;
reg  [7:0] preamble_addr; // Needs to be 8-bit to address 0-159
// Instantiation of ROMs 
l_stf_rom l_stf_rom (
    .addr(preamble_addr[3:0]), // L_STF uses 10 samples (addr 0-9), so 4 bits are enough
    .dout(l_stf)
);

l_ltf_rom l_ltf_rom (
    .addr(preamble_addr[7:0]), // L_LTF uses 10 samples (addr 0-9) + 6 for GI, but preamble_addr can go up to 159.
                               // Ensured with this `addr` width matches the ROM definition if it's larger than 4 bits for L_LTF
    .dout(l_ltf)
);

//////////////////////////////////////////////////////////////////////////
// HT SHORT + LONG PREAMBLE ROMs
//////////////////////////////////////////////////////////////////////////
wire [31:0] ht_stf;
wire [31:0] ht_ltf;
// Instantiation of ROMs 
ht_stf_rom ht_stf_rom (
    .addr(preamble_addr[3:0]), // HT-STF uses 5 samples (addr 0-4), so 4 bits are enough
    .dout(ht_stf)
);

ht_ltf_rom ht_ltf_rom (
    .addr(preamble_addr[6:0]), // HT-LTF uses 4 samples (addr 0-3) + 64 (IFFT size), needs 7 bits (0-79)
    .dout(ht_ltf)
);

//////////////////////////////////////////////////////////////////////////
// Cyclic redundancy check (CRC32) and frame check sequence (FCS) block
//////////////////////////////////////////////////////////////////////////
wire        crc_en;
wire [3:0]  crc_data;
wire [31:0] pkt_fcs;
reg  [4:0]  pkt_fcs_idx;
reg  [3:0]  bram_din_last_nibble; // Register to hold the last nibble of bram_din

//////////////////////////////////////////////////////////////////////////
// Store scrambled bits into axi stream fifo (bits_enc_fifo)
//////////////////////////////////////////////////////////////////////////
wire [1:0]  bits_enc_fifo_idata;
wire        bits_enc_fifo_ivalid, bits_enc_fifo_ovalid;
wire        bits_enc_fifo_iready, bits_enc_fifo_oready;
wire [15:0] bits_enc_fifo_space;
wire [1:0]  bits_enc_fifo_odata;

always @(posedge clk) begin
    if (reset_int) begin
        bram_din_last_nibble <= 4'b0; // Initialize to avoid X
    end else if (bits_enc_fifo_iready) begin
        // Only update if the FIFO is ready to accept bits, implying data is being read from BRAM
        bram_din_last_nibble <= bram_din[63:60];
    end
end

// Combinational logic for crc_data (using ternary operators for conditional assignment)
assign crc_data[0] = (state1 == S1_DATA && state11 == S11_PSDU_DATA) ? (psdu_bit_cnt[5:0] == 6'b111111 ? bram_din_last_nibble[0] : bram_din[(psdu_bit_cnt[5:2] << 2) + 0]) : 1'b0;
assign crc_data[1] = (state1 == S1_DATA && state11 == S11_PSDU_DATA) ? (psdu_bit_cnt[5:0] == 6'b111111 ? bram_din_last_nibble[1] : bram_din[(psdu_bit_cnt[5:2] << 2) + 1]) : 1'b0;
assign crc_data[2] = (state1 == S1_DATA && state11 == S11_PSDU_DATA) ? (psdu_bit_cnt[5:0] == 6'b111111 ? bram_din_last_nibble[2] : bram_din[(psdu_bit_cnt[5:2] << 2) + 2]) : 1'b0;
assign crc_data[3] = (state1 == S1_DATA && state11 == S11_PSDU_DATA) ? (psdu_bit_cnt[5:0] == 6'b111111 ? bram_din_last_nibble[3] : bram_din[(psdu_bit_cnt[5:2] << 2) + 3]) : 1'b0;

crc32_tx fcs_inst (
    .clk(clk),
    .rst(reset_int),
    .crc_en(crc_en),
    .data_in(crc_data),
    .crc_out(pkt_fcs)
);
assign crc_en = (bits_enc_fifo_iready == 1 && state1 == S1_DATA && state11 == S11_PSDU_DATA && psdu_bit_cnt[1:0] == 2'b11);

//////////////////////////////////////////////////////////////////////////
// bit source selection and scrambling operation
//////////////////////////////////////////////////////////////////////////
reg         bit_scram;
reg [6:0] data_scram_state;

// All paths assign a value to bit_scram, so no latches are inferred,
// and it should not generate 'X' if its inputs are valid.
always @* begin
    bit_scram = 1'b0; // Default assignment to ensure all paths define it

    // Legacy PLCP [rate + reserved + length + parity + tail] and HT PLCP [MCS + length + reserved + short/long GI + CRC + tail] fields
    if(state1 == S1_L_SIG || state1 == S1_HT_SIG) begin
        bit_scram = bram_din[plcp_bit_cnt];
    end
    // DATA [service + PSDU + CRC + tail + pad] fields
    else if(state1 == S1_DATA) begin
        // PLCP service field
        if(state11 == S11_SERVICE) begin
            bit_scram = data_scram_state[6] ^ data_scram_state[3] ^ 1'b0; // XOR with 0 or a fixed bit
        // PSDU DATA field
        end else if(state11 == S11_PSDU_DATA) begin
            if(psdu_bit_cnt[5:2] == 4'b1111) // Assuming 6 bits for psdu_bit_cnt, this condition is psdu_bit_cnt[5:2] which is 4 bits
                bit_scram = data_scram_state[6] ^ data_scram_state[3] ^ bram_din_last_nibble[psdu_bit_cnt[1:0]];
            else
                bit_scram = data_scram_state[6] ^ data_scram_state[3] ^ bram_din[psdu_bit_cnt[5:0]];
        // PSDU CRC field
        end else if(state11 == S11_PSDU_CRC) begin
            bit_scram = data_scram_state[6] ^ data_scram_state[3] ^ pkt_fcs[pkt_fcs_idx];
        // DATA tail field
        end else if(state11 == S11_TAIL) begin
            bit_scram = 1'b0; // All tail bits are 0
        // DATA pad field
        end else if(state11 == S11_PAD) begin
            bit_scram = data_scram_state[6] ^ data_scram_state[3] ^ 1'b0; // XOR with 0 or a fixed bit
        end
    end
end

//////////////////////////////////////////////////////////////////////////
// Convolutional encoding
//////////////////////////////////////////////////////////////////////////
wire        enc_reset;
wire        enc_en;
wire [1:0] bits_enc;
// Instantiation of convolutional encoder (assuming this module exists)
convenc convenc (
    .clk(clk),
    .rst(enc_reset),
    .enc_en(enc_en),
    .bit_in(bit_scram),
    .bits_out(bits_enc)
);
assign enc_reset = phy_tx_arest | (state1 == S1_WAIT_PKT) | (plcp_bit_cnt == 23) | (plcp_bit_cnt == 47);
assign enc_en = (state1 >= S1_L_SIG) && (state11 != S11_RESET) && bits_enc_fifo_iready;

//////////////////////////////////////////////////////////////////////////
// DOT11 TX FINITE STATE MACHINE 1
//////////////////////////////////////////////////////////////////////////
reg [2:0]  N_BPSC;
reg [8:0]  N_DBPS;
reg [4:0]  RATE;
reg [18:0] PSDU_BIT_LEN;
reg        HT_AGGR;
reg        S_GI;
reg [8:0]  dbps_cnt_FSM1;

always @(posedge clk) begin
    if (reset_int) begin
        bram_addr <= 10'b0; // Initialize bram_addr
        N_BPSC <= 3'b0;
        N_DBPS <= 9'b0;
        RATE <= 5'b0;
        PSDU_BIT_LEN <= 19'b0;
        HT_AGGR <= 1'b0;
        S_GI <= 1'b0;
        plcp_bit_cnt <= 6'b0;
        service_bit_cnt <= 4'b0;
        psdu_bit_cnt <= 19'b0;
        pkt_fcs_idx <= 5'b0;
        dbps_cnt_FSM1 <= 9'b0;
        ofdm_cnt_FSM1 <= 15'b0;
        data_scram_state <= 7'b0; // Initialize data_scram_state
        state1 <= S1_WAIT_PKT;
        state11 <= S11_SERVICE;
    end else if(bits_enc_fifo_iready == 1) begin // State transitions for FSM1 are gated by fifo_iready
        case(state1)
        S1_WAIT_PKT: begin
            if(phy_tx_start) begin
                bram_addr <= 10'b0;
                plcp_bit_cnt <= 6'b0;
                state1 <= S1_L_SIG;
            end
        end

        S1_L_SIG: begin
            plcp_bit_cnt <= plcp_bit_cnt + 1'b1;
            if(plcp_bit_cnt == 6'd0) begin // First clock cycle of L_SIG state
                case(bram_din[3:0]) // RATE field from PLCP (4 bits)
                    4'b1011: begin N_BPSC <= 3'd1; N_DBPS <= 9'd24; RATE <= 5'b01011; end  // 6 Mbps
                    4'b1111: begin N_BPSC <= 3'd1; N_DBPS <= 9'd36; RATE <= 5'b01111; end  // 9 Mbps
                    4'b1010: begin N_BPSC <= 3'd2; N_DBPS <= 9'd48; RATE <= 5'b01010; end  // 12 Mbps
                    4'b1110: begin N_BPSC <= 3'd2; N_DBPS <= 9'd72; RATE <= 5'b01110; end  // 18 Mbps
                    4'b1001: begin N_BPSC <= 3'd4; N_DBPS <= 9'd96; RATE <= 5'b01001; end  // 24 Mbps
                    4'b1101: begin N_BPSC <= 3'd4; N_DBPS <= 9'd144; RATE <= 5'b01101; end // 36 Mbps
                    4'b1000: begin N_BPSC <= 3'd6; N_DBPS <= 9'd192; RATE <= 5'b01000; end // 48 Mbps
                    4'b1100: begin N_BPSC <= 3'd6; N_DBPS <= 9'd216; RATE <= 5'b01100; end // 54 Mbps
                    default: begin N_BPSC <= 3'd1; N_DBPS <= 9'd24; RATE <= 5'b01011; end  // Default to 6 Mbps
                endcase
                PSDU_BIT_LEN <= {4'd0, bram_din[16:5], 3'd0}; // PSDU_LEN is 12 bits, shifted for total bits
                PKT_TYPE <= bram_din[24]; // L_SIG Packet Type bit
            end else if(plcp_bit_cnt == 6'd22) begin // One cycle before L_SIG ends
                bram_addr <= 10'd1; // Next BRAM address for HT_SIG or DATA
            end else if(plcp_bit_cnt == 6'd23) begin // Last cycle of L_SIG
                ofdm_cnt_FSM1 <= ofdm_cnt_FSM1 + 1'b1;
                plcp_bit_cnt <= 6'b0; // Reset PLCP bit counter for next PLCP (HT_SIG) or DATA

                // Transition based on packet type
                if(RATE == 5'b01011 && PKT_TYPE == HT) begin // If L_SIG rate implies HT and packet is HT
                    state1 <= S1_HT_SIG; // Go to HT_SIG state
                end else begin // Legacy packet
                    PKT_TYPE <= LEGACY; // Explicitly set to LEGACY
                    service_bit_cnt <= 4'b0;
                    data_scram_state <= init_data_scram_state; // Initialize scrambler for data
                    dbps_cnt_FSM1 <= 9'b0;
                    state1 <= S1_DATA;
                    state11 <= S11_SERVICE; // Start with Service Field
                end
            end
        end

        S1_HT_SIG: begin
            plcp_bit_cnt <= plcp_bit_cnt + 1'b1;
            if(plcp_bit_cnt == 6'd0) begin // First clock cycle of HT_SIG state
                case(bram_din[2:0]) // MCS field from PLCP (3 bits)
                    3'b000:  begin N_BPSC <= 3'd1; N_DBPS <= 9'd26;  RATE <= 5'b10000; end // 6.5 Mbps
                    3'b001:  begin N_BPSC <= 3'd2; N_DBPS <= 9'd52;  RATE <= 5'b10001; end // 13.0 Mbps
                    3'b010:  begin N_BPSC <= 3'd2; N_DBPS <= 9'd78;  RATE <= 5'b10010; end // 19.5 Mbps
                    3'b011:  begin N_BPSC <= 3'd4; N_DBPS <= 9'd104; RATE <= 5'b10011; end // 26.0 Mbps
                    3'b100:  begin N_BPSC <= 3'd4; N_DBPS <= 9'd156; RATE <= 5'b10100; end // 39.0 Mbps
                    3'b101:  begin N_BPSC <= 3'd6; N_DBPS <= 9'd208; RATE <= 5'b10101; end // 52.0 Mbps
                    3'b110:  begin N_BPSC <= 3'd6; N_DBPS <= 9'd234; RATE <= 5'b10110; end // 58.5 Mbps
                    3'b111:  begin N_BPSC <= 3'd6; N_DBPS <= 9'd260; RATE <= 5'b10111; end // 65.0 Mbps
                    default: begin N_BPSC <= 3'd1; N_DBPS <= 9'd26;  RATE <= 5'b10000; end // Default to 6.5 Mbps
                endcase
                PSDU_BIT_LEN <= {bram_din[23:8], 3'd0}; // PSDU_LEN is 16 bits, shifted for total bits
                HT_AGGR <= bram_din[27]; // HT Aggregation bit
                S_GI <= bram_din[31]; // Short Guard Interval bit
            end else if(plcp_bit_cnt == 6'd23) begin // End of first HT-SIG OFDM symbol
                ofdm_cnt_FSM1 <= ofdm_cnt_FSM1 + 1'b1;
            end else if(plcp_bit_cnt == 6'd47) begin // End of second HT-SIG OFDM symbol
                ofdm_cnt_FSM1 <= ofdm_cnt_FSM1 + 1'b1;

                service_bit_cnt <= 4'b0;
                data_scram_state <= init_data_scram_state; // Initialize scrambler for data
                dbps_cnt_FSM1 <= 9'b0;

                state1 <= S1_DATA;
                state11 <= S11_SERVICE; // Start with Service Field
            end
        end

        S1_DATA: begin
            // Data scrambler update (LFSR)
            data_scram_state <= {data_scram_state[5:0], (data_scram_state[3] ^ data_scram_state[6])};

            // Sub-state machine for DATA field
            case(state11)
            S11_SERVICE: begin
                service_bit_cnt <= service_bit_cnt + 1'b1;
                if(service_bit_cnt == 4'd14) begin // One cycle before service field ends
                    bram_addr <= 10'd2; // Move to actual PSDU data in BRAM
                end else if(service_bit_cnt == 4'd15) begin // End of service field (16 bits)
                    psdu_bit_cnt <= 19'b0;
                    state11 <= S11_PSDU_DATA; // Move to PSDU data
                end
            end

            S11_PSDU_DATA: begin
                psdu_bit_cnt <= psdu_bit_cnt + 1'b1;
                // Transition logic for CRC or Tail based on HT_AGGR and PSDU length
                if((HT_AGGR == 1'b0) && (psdu_bit_cnt == PSDU_BIT_LEN-19'd33)) // Legacy: (PSDU + Tail + Pad) - 32 bits for CRC = PSDU_BIT_LEN-33
                    state11 <= S11_PSDU_CRC;
                else if((HT_AGGR == 1'b1) && (psdu_bit_cnt == PSDU_BIT_LEN-1'b1)) // HT: PSDU ends here, then Tail + Pad
                    state11 <= S11_TAIL;
            end

            S11_PSDU_CRC: begin
                psdu_bit_cnt <= psdu_bit_cnt + 1'b1;
                pkt_fcs_idx <= pkt_fcs_idx + 1'b1;
                if(psdu_bit_cnt == PSDU_BIT_LEN - 1'b1) // End of CRC (32 bits)
                    state11 <= S11_TAIL;
            end

            S11_TAIL: begin
                // data_scram_state <= data_scram_state; // Scrambler holds its state for tail bits (all 0s)
                psdu_bit_cnt <= psdu_bit_cnt + 1'b1;
                if(psdu_bit_cnt == PSDU_BIT_LEN + 19'd5) // After 6 tail bits (PSDU_BIT_LEN + 6)
                    state11 <= S11_PAD;
            end

            S11_PAD: begin
                psdu_bit_cnt <= psdu_bit_cnt + 1'b1;
                if(dbps_cnt_FSM1 == 9'b0) begin // Last bit of current OFDM symbol (padded to N_DBPS)
                    state11 <= S11_RESET; // Indicate end of data for current OFDM symbol
                end
            end

            S11_RESET: begin
                // FSM11 stays here until FSM1 resets it
            end
            default: begin // Ensure all states are covered, or default to a known state
                state11 <= S11_SERVICE;
            end
            endcase
           // This condition is for when the current BRAM word is consumed.
            // psdu_bit_cnt[5:0] == 6'b111110 (62) for 64-bit word (bits 0-63)
            // It suggests that bram_din provides 64 bits at once, and psdu_bit_cnt increments by 1 for each bit.
            if(state11 <= S11_PSDU_DATA && psdu_bit_cnt[5:0] == 6'd62)
                bram_addr <= bram_addr + 1'b1;

            // Update dbps (bits per symbol) and ofdm symbol counters
            if(state11 <= S11_PAD) begin // Only count if processing active data/padding
                if(dbps_cnt_FSM1 == N_DBPS-1'b1) begin // End of current OFDM symbol's data bits
                    dbps_cnt_FSM1 <= 9'b0;
                    ofdm_cnt_FSM1 <= ofdm_cnt_FSM1 + 1'b1;
                end else begin
                    dbps_cnt_FSM1 <= dbps_cnt_FSM1 + 1'b1;
                end
            end
        end

        default: begin // For any unhandled state1, go back to WAIT_PKT
            state1 <= S1_WAIT_PKT;
            state11 <= S11_SERVICE; // Also reset sub-state
        end
        endcase
    end
    // else if bits_enc_fifo_iready is 0 or X, state1 and state11 hold their values.
    // This implies that FSM1 pauses when the encoding FIFO is not ready.
    // This is a common and usually desired behavior.
    // If bits_enc_fifo_iready becomes X, then the comparison bits_enc_fifo_iready == 1 will yield X,
    // causing 'state1' to go X. This is why it's better to explicitly handle 'X' or treat it as '0'.
    // A robust way to handle this might be:
    // else if (!bits_enc_fifo_iready || bits_enc_fifo_iready == 1'bx) begin /* do nothing, hold state */ end
    // For simulation, `bits_enc_fifo_iready == 1` being `X` will propagate `X`.
    // For synthesis, tools typically interpret `X` as `0` for control signals or latch `X` values.
    // Given the testbench drives it, `X` should only propagate if FIFO itself outputs `X`.
end


// Instantiation of AXI Stream FIFO (assuming this module exists)
axi_fifo_bram #(.WIDTH(2), .SIZE(10)) bits_enc_fifo(
    .clk(clk), .reset(reset_int), .clear(reset_int),
    .i_tdata(bits_enc_fifo_idata), .i_tvalid(bits_enc_fifo_ivalid), .i_tready(bits_enc_fifo_iready),
    .o_tdata(bits_enc_fifo_odata), .o_tvalid(bits_enc_fifo_ovalid), .o_tready(bits_enc_fifo_oready),
    .space(bits_enc_fifo_space), .occupied()
);
wire [1:0]  punc_info; // Output from punc_interlv_lut
reg         enc_pos;   // Encoding position toggle bit

assign bits_enc_fifo_idata  = bits_enc; // Input data to FIFO
// Valid when not in WAIT_PKT and not in S11_RESET
assign bits_enc_fifo_ivalid = (state1 != S1_WAIT_PKT) && (state11 < S11_RESET);
// FIFO output ready signal driven by FSM2
assign bits_enc_fifo_oready = (state2 == S2_PUNC_INTERLV) && (bits_enc_fifo_ovalid == 1'b1) && ((enc_pos == 1'b1) || (|punc_info == 1'b1));

//////////////////////////////////////////////////////////////////////////
// Bit puncturing and bit interleaving
//////////////////////////////////////////////////////////////////////////
// Puncturing and interleaving index look up table
reg  [14:0] ofdm_cnt_FSM2;
reg  [8:0]  dbps_cnt_FSM2;
wire [17:0] interlv_addrs; // Address for bits_ram

// Instantiation of LUT (assuming this module exists)
punc_interlv_lut punc_interlv_lut(
    .rate(PKT_TYPE == LEGACY ? (ofdm_cnt_FSM2 > 15'd0 ? RATE : 5'b01011) : (ofdm_cnt_FSM2 > 15'd2 ? RATE : 5'b01011)), // Use 6Mbps for preambles
    .idx_i(dbps_cnt_FSM2),
    .idx_o(interlv_addrs),
    .punc_o(punc_info)
);

// This is a RAM module for holding convolutionally encoded, punctured and interleaved bits.
// Bit puncturing is implicitly carried out by selecting appropriate write address and data.
wire        bits_ram_en;
wire        punc_bit; // Data to write to bits_ram
wire [8:0] bits_ram_waddr; // Write address for bits_ram
reg  [5:0] mod_addr; // Read address for bits_ram (for modulation)
wire [5:0] bits_to_mod; // Data read from bits_ram (for modulation)

// Instantiation of RAM (assuming this module exists)
ram_simo #(.DEPTH(52)) bits_ram( // Assuming DEPTH refers to number of 6-bit words (52 subcarriers - 4 pilots)
    .clk(clk),
    .waddr(bits_ram_waddr),
    .raddr(mod_addr),
    .wen(bits_ram_en),
    .data_i(punc_bit),
    .data_o(bits_to_mod)
);

// Determine write address and data based on puncturing and encoding position
assign bits_ram_waddr = (enc_pos == 1'b1) ? interlv_addrs[17:9] : (punc_info[0] == 1'b0 ? interlv_addrs[8:0] : interlv_addrs[17:9]);
assign bits_ram_en = (state2 == S2_PUNC_INTERLV); // Enable write when in puncturing/interleaving state
assign punc_bit = (enc_pos == 1'b1) ? bits_enc_fifo_odata[0] : (punc_info[0] == 1'b0 ? bits_enc_fifo_odata[1] : bits_enc_fifo_odata[0]);

//////////////////////////////////////////////////////////////////////////
// Bits modulation
//////////////////////////////////////////////////////////////////////////
// BPSK, QPSK, 16-QAM and 64-QAM modulation
wire [31:0] mod_IQ; // Output I/Q pair from modulation (16-bit I, 16-bit Q)
// Instantiation of modulation block (assuming this module exists)
modulation modulation_inst (
    .N_BPSC(PKT_TYPE == LEGACY ? (ofdm_cnt_FSM2 > 15'd0 ? N_BPSC : 3'd1) : (ofdm_cnt_FSM2 > 15'd2 ? N_BPSC : 3'd1)), // N_BPSC for preambles is 1
    .bits_in(bits_to_mod),
    .IQ(mod_IQ)
);

//////////////////////////////////////////////////////////////////////////
// PILOT, DC (0Hz) and sideband(SB) insertion
//////////////////////////////////////////////////////////////////////////
reg  [31:0] pilot_iq [0:3]; // Array for 4 pilot subcarriers (32-bit I/Q)
reg  [6:0]  pilot_scram_state; // Pilot scrambler state
reg  [3:0]  ht_polarity; // HT polarity sequence
wire        pilot_gain = pilot_scram_state[6] ^ pilot_scram_state[3] ^ 1'b0; // Scrambled pilot gain (0 or 1)
wire [31:0] DC_SB_IQ = {16'h0000, 16'h0000}; // DC and Sideband carriers are 0

//////////////////////////////////////////////////////////////////////////
// Inverse Fast Fourier Transform (IFFT)
//////////////////////////////////////////////////////////////////////////
reg [31:0] ifft_iq; // Input to IFFT (I/Q pair)
reg [7:0]  iq_cnt; // Counter for 64-point IFFT input
// Combinational block to select IFFT input based on iq_cnt and FSM2 state
always @* begin
    ifft_iq = 32'b0; // Default to 0 to prevent X if no condition met

    if(state2 == S2_MOD_IFFT_INPUT) begin
        if(iq_cnt == 8'd0 || ((PKT_TYPE == LEGACY || (PKT_TYPE == HT && ofdm_cnt_FSM2 <= 15'd2)) && iq_cnt >= 8'd27 && iq_cnt < 8'd38) || (PKT_TYPE == HT && ofdm_cnt_FSM2 > 15'd2 && iq_cnt >= 8'd29 && iq_cnt < 8'd36)) begin
            // DC and Null subcarriers (indices 0, 27-37 for Legacy/HT preambles, 29-35 for HT data)
            ifft_iq = DC_SB_IQ;
        end else if(iq_cnt == 8'd7) begin // Pilot at index 7
            ifft_iq = pilot_iq[2]; // Corresponds to P3 (index 7)
        end else if(iq_cnt == 8'd21) begin // Pilot at index 21
            ifft_iq = pilot_iq[3]; // Corresponds to P4 (index 21)
        end else if(iq_cnt == 8'd43) begin // Pilot at index 43
            ifft_iq = pilot_iq[0]; // Corresponds to P1 (index 43)
        end else if(iq_cnt == 8'd57) begin // Pilot at index 57
            ifft_iq = pilot_iq[1]; // Corresponds to P2 (index 57)
        end else if(iq_cnt < 8'd64) begin // Data subcarriers
            if(PKT_TYPE == HT && (ofdm_cnt_FSM2 == 15'd1 || ofdm_cnt_FSM2 == 15'd2)) begin // HT-SIG uses a different IQ mapping
                ifft_iq = {mod_IQ[15:0], mod_IQ[31:16]}; // Swap I and Q
            end else begin
                ifft_iq = mod_IQ;
            end
        end
    end
end

reg         ifft_ce; // Clock enable for IFFT
wire        ifft_o_sync; // IFFT output sync signal
wire [31:0] ifft_o_result; // IFFT output data
// Instantiation of IFFT (assuming this module exists)
ifftmain ifft64(
    .i_clk(clk),
    .i_reset(reset_int),
    .i_ce(ifft_ce), // Clock enable for IFFT
    .i_sample(ifft_iq),
    .o_result(ifft_o_result),
    .o_sync(ifft_o_sync)
);

//////////////////////////////////////////////////////////////////////////
// DOT11 TX FINITE STATE MACHINE 2 (IQ sample generation)
//////////////////////////////////////////////////////////////////////////
wire [8:0]  dbps_size; // Bits per symbol size for current packet type/state
wire [15:0] pkt_fifo_space; // Available space in Packet FIFO
wire [15:0] CP_fifo_space;  // Available space in Cyclic Prefix FIFO

always @(posedge clk) begin
    if (reset_int) begin
        dbps_cnt_FSM2 <= 9'b0;
        enc_pos <= 1'b0;
        ofdm_cnt_FSM2 <= 15'b0;
        iq_cnt <= 8'b0;
        ifft_ce <= 1'b0;
        mod_addr <= 6'b0;
        pilot_scram_state <= init_pilot_scram_state; // Initialize pilot scrambler
        ht_polarity <= 4'b1000; // Initialize HT polarity
        state2 <= S2_PUNC_INTERLV;
    end else begin
        case(state2)
        S2_PUNC_INTERLV: begin
            if((pkt_fifo_space > 15'd63) && (CP_fifo_space > 15'd15) && (bits_enc_fifo_ovalid == 1'b1)) begin
                // The encoding position is shifted only if encoded bits are not punctured (punc_info[0] is 0)
                if(|punc_info == 1'b0) // If punc_info is all zeros
                    enc_pos <= ~enc_pos; // Toggle enc_pos if not puncturing

                // If encoding position is on the second place (enc_pos == 1) OR if encoded bits are punctured (punc_info[0] == 1)
                if((enc_pos == 1'b1) || (|punc_info == 1'b1)) begin
                    if(dbps_cnt_FSM2 == dbps_size-1'b1) begin // End of current OFDM symbol's data bits
                        dbps_cnt_FSM2 <= 9'b0;
                        state2 <= S2_PILOT_DC_SB; // Move to pilot/DC/SB insertion state
                    end else begin
                        dbps_cnt_FSM2 <= dbps_cnt_FSM2 + 1'b1;
                    end
                end
            end
        end

        S2_PILOT_DC_SB: begin
            if(PKT_TYPE == HT && ofdm_cnt_FSM2 > 15'd2) begin // HT data pilots
                if((ht_polarity[0] ^ pilot_gain) == 1'b0)
                    pilot_iq[0] <= {16'h4000, 16'h0000}; // (0.5, 0)
                else
                    pilot_iq[0] <= {16'hC000, 16'h0000}; // (-0.5, 0)

                if((ht_polarity[1] ^ pilot_gain) == 1'b0)
                    pilot_iq[1] <= {16'h4000, 16'h0000};
                else
                    pilot_iq[1] <= {16'hC000, 16'h0000};

                if((ht_polarity[2] ^ pilot_gain) == 1'b0)
                    pilot_iq[2] <= {16'h4000, 16'h0000};
                else
                    pilot_iq[2] <= {16'hC000, 16'h0000};

                if((ht_polarity[3] ^ pilot_gain) == 1'b0)
                    pilot_iq[3] <= {16'h4000, 16'h0000};
                else
                    pilot_iq[3] <= {16'hC000, 16'h0000};

                ht_polarity <= {ht_polarity[0], ht_polarity[3:1]}; // Rotate HT polarity
            end else begin // Legacy or HT preamble pilots
                if(pilot_gain == 1'b0) begin
                    pilot_iq[0] <= {16'h4000, 16'h0000};
                    pilot_iq[1] <= {16'h4000, 16'h0000};
                    pilot_iq[2] <= {16'h4000, 16'h0000};
                    pilot_iq[3] <= {16'hC000, 16'h0000};
                end else begin
                    pilot_iq[0] <= {16'hC000, 16'h0000};
                    pilot_iq[1] <= {16'hC000, 16'h0000};
                    pilot_iq[2] <= {16'hC000, 16'h0000};
                    pilot_iq[3] <= {16'h4000, 16'h0000};
                end
            end
            pilot_scram_state <= {pilot_scram_state[5:0], (pilot_scram_state[3] ^ pilot_scram_state[6])}; // Update pilot scrambler (LFSR)

            iq_cnt <= 8'b0; // Reset IFFT input counter
            ifft_ce <= 1'b1; // Enable IFFT
            state2 <= S2_MOD_IFFT_INPUT; // Move to IFFT input generation state
        end

        S2_MOD_IFFT_INPUT: begin
            if(iq_cnt < 8'd63) begin // Not last IFFT input cycle
                // Modulo address calculation based on packet type and iq_cnt
                if(PKT_TYPE == HT && ofdm_cnt_FSM2 > 15'd2) begin // HT data
                    if(iq_cnt < 8'd6)
                        mod_addr <= iq_cnt[5:0] + 6'd26;
                    else if(iq_cnt < 8'd20)
                        mod_addr <= iq_cnt[5:0] + 6'd25;
                    else if(iq_cnt < 8'd28)
                        mod_addr <= iq_cnt[5:0] + 6'd24;
                    else if(iq_cnt < 8'd42)
                        mod_addr <= iq_cnt[5:0] - 6'd35;
                    else if(iq_cnt < 8'd56)
                        mod_addr <= iq_cnt[5:0] - 6'd36;
                    else // if(iq_cnt < 63)
                        mod_addr <= iq_cnt[5:0] - 6'd37;
                end else begin // Legacy or HT preamble
                    if(iq_cnt < 8'd6)
                        mod_addr <= iq_cnt[5:0] + 6'd24;
                    else if(iq_cnt < 8'd20)
                        mod_addr <= iq_cnt[5:0] + 6'd23;
                    else if(iq_cnt < 8'd28)
                        mod_addr <= iq_cnt[5:0] + 6'd22;
                    else if(iq_cnt < 8'd42)
                        mod_addr <= iq_cnt[5:0] - 6'd37;
                    else if(iq_cnt < 8'd56)
                        mod_addr <= iq_cnt[5:0] - 6'd38;
                    else // if(iq_cnt < 63)
                        mod_addr <= iq_cnt[5:0] - 6'd39;
                end
                iq_cnt <= iq_cnt + 1'b1; // Increment IFFT input counter
            end else begin // Last IFFT input cycle
                ifft_ce <= 1'b0; // Disable IFFT
                ofdm_cnt_FSM2 <= ofdm_cnt_FSM2 + 1'b1; // Increment OFDM symbol counter for FSM2
                state2 <= S2_RESET; // Move to reset/idle state for FSM2
            end
        end

        S2_RESET: begin
            // This is not the last OFDM symbol processed
            if(ofdm_cnt_FSM2 < ofdm_cnt_FSM1) begin // More OFDM symbols to process
                state2 <= S2_PUNC_INTERLV; // Go back to puncturing/interleaving
            end else if(state11 == S11_RESET) begin // FSM11 indicates end of packet data
                // This condition seems to be for flushing remaining data or ensuring pipeline
                // is empty. Consider whether ifft_ce should be asserted here or not.
                // Currently, it's enabled if FIFOs have space, suggesting a flush or idle sequence.
                if((pkt_fifo_space > 15'd2) && (CP_fifo_space > 15'd2))
                    ifft_ce <= 1'b1;
                else
                    ifft_ce <= 1'b0;
            end
        end

        default: begin // For any unhandled state2, go back to PUNC_INTERLV
            state2 <= S2_PUNC_INTERLV;
        end
        endcase
    end
end
// dbps_size assignment (combinational)
assign dbps_size = PKT_TYPE == LEGACY ? (ofdm_cnt_FSM2 > 15'd0 ? N_DBPS : 9'd24) : (ofdm_cnt_FSM2 > 15'd2 ? N_DBPS : 9'd24);

//////////////////////////////////////////////////////////////////////////
// Count number of [pkt/CP] IQ samples to send (IFFT Output Logic)
//////////////////////////////////////////////////////////////////////////
reg         ifft_status; // Indicates if IFFT has started outputting
reg         ifft_ce_reg; // Registered ifft_ce
reg [31:0] ifft_o_result_reg; // Registered IFFT output
reg [5:0]  ifft_o_iq_cnt; // Counter for IQ samples from IFFT (0-63 for packet, 0-15 for CP)
reg [14:0] ifft_o_sync_cnt; // Count IFFT sync pulses
reg [20:0] nof_iq2send;   // Total number of IQ samples to send for the entire packet

always @(posedge clk) begin
    if (reset_int) begin
        ifft_o_iq_cnt <= 6'b0;
        ifft_o_sync_cnt <= 15'b0;
        ifft_status <= NO_OUTPUT_YET; // Initialize status
        nof_iq2send <= 21'd320; // Initial value for preambles (assuming it's fixed or loaded)
    end else begin
        ifft_o_result_reg <= ifft_o_result; // Register IFFT output
        ifft_ce_reg <= ifft_ce;             // Register IFFT enable

        if(ifft_o_sync == 1'b1) begin // If IFFT outputs a sync pulse (start of a new OFDM symbol)
            ifft_o_sync_cnt <= ifft_o_sync_cnt + 1'b1;
            // The moment ifft outputs the first result, we change the status
            if(ifft_status == NO_OUTPUT_YET)
                ifft_status <= OUTPUT_STARTED;
        end

        // IFFT output counter (counts valid IFFT samples when IFFT is enabled)
        if((ifft_status == OUTPUT_STARTED) && (ifft_ce == 1'b1)) // Only count if IFFT is enabled AND has started
            ifft_o_iq_cnt <= ifft_o_iq_cnt + 1'b1;
        else
            ifft_o_iq_cnt <= 6'b0; // Reset when IFFT is not outputting (e.g., between symbols)


        // Total IQ samples to send update (driven by FSM2's state transition to PILOT_DC_SB)
        if(state2 == S2_PILOT_DC_SB) begin
            if(PKT_TYPE == HT) begin
                if(nof_iq2send == 21'd480) // This condition seems for a specific HT preamble part
                    nof_iq2send <= nof_iq2send + 21'd240; // Add HT-LTF samples (240 = 2*120, assuming 2 LTFs)
                else if((nof_iq2send < 21'd480) || (S_GI == 1'b0)) // HT preamble or non-short GI
                    nof_iq2send <= nof_iq2send + 21'd80; // Add 80 samples (OFDM symbol + CP)
                else // S_GI == 1 (Short Guard Interval)
                    nof_iq2send <= nof_iq2send + 21'd72; // Add 72 samples (OFDM symbol + Short CP)
            end else begin // Legacy packet
                nof_iq2send <= nof_iq2send + 21'd80; // Add 80 samples (OFDM symbol + CP)
            end
        end
    end
end

//////////////////////////////////////////////////////////////////////////
// Cyclic Prefix IFFT output -> Axi stream fifo (CP_fifo)
//////////////////////////////////////////////////////////////////////////
wire [31:0] CP_fifo_idata,  CP_fifo_odata;
wire        CP_fifo_ivalid, CP_fifo_ovalid;
wire        CP_fifo_iready, CP_fifo_oready;
//wire [15:0] CP_fifo_space; // Redundant declaration, already defined at top. This is just for local visibility.
reg         fifo_turn; // Decides which FIFO (CP or PKT) data is taken from for output

// Instantiation of AXI Stream FIFO (assuming this module exists)
axi_fifo_bram #(.WIDTH(32), .SIZE(6)) CP_fifo( // Size 6 for CP (16 samples per CP * 4 = 64 / 32 = 2. But 6? For 20MHz?)
    .clk(clk), .reset(reset_int), .clear(reset_int),
    .i_tdata(CP_fifo_idata), .i_tvalid(CP_fifo_ivalid), .i_tready(CP_fifo_iready),
    .o_tdata(CP_fifo_odata), .o_tvalid(CP_fifo_ovalid), .o_tready(CP_fifo_oready),
    .space(CP_fifo_space), .occupied()
);
assign CP_fifo_idata  = ifft_o_result_reg; // Input data from registered IFFT output
// CP_fifo_ivalid logic: Valid when IFFT output count corresponds to CP samples
assign CP_fifo_ivalid = (S_GI == 1'b1 && ifft_o_sync_cnt > 15'd3) ? (ifft_o_iq_cnt[5:3] == 3'b111 ? ifft_ce_reg : 1'b0) : (ifft_o_iq_cnt[5:4] == 2'b11 ? ifft_ce_reg : 1'b0);
// CP_fifo_oready: Ready if FSM3 is in L_SIG, HT_SIG, or DATA state AND it's CP_FIFO's turn AND result_iq_ready is high
assign CP_fifo_oready = ((state3 == S3_L_SIG) || (state3 == S3_HT_SIG) || (state3 == S3_DATA)) && (fifo_turn == CP_FIFO) ? result_iq_ready : 1'b0;

//////////////////////////////////////////////////////////////////////////
// Packet IFFT output -> Axi stream fifo (pkt_fifo)
//////////////////////////////////////////////////////////////////////////
wire [31:0] pkt_fifo_idata,  pkt_fifo_odata;
wire        pkt_fifo_ivalid, pkt_fifo_ovalid;
wire        pkt_fifo_iready, pkt_fifo_oready;
//wire [15:0] pkt_fifo_space; // Redundant declaration
// Instantiation of AXI Stream FIFO (assuming this module exists)
axi_fifo_bram #(.WIDTH(32), .SIZE(8)) pkt_fifo( // Size 8 for packet (64 samples per OFDM symbol / 32-bit words = 2)
    .clk(clk), .reset(reset_int), .clear(reset_int),
    .i_tdata(pkt_fifo_idata), .i_tvalid(pkt_fifo_ivalid), .i_tready(pkt_fifo_iready),
    .o_tdata(pkt_fifo_odata), .o_tvalid(pkt_fifo_ovalid), .o_tready(pkt_fifo_oready),
    .space(pkt_fifo_space), .occupied()
);
reg [20:0] pkt_iq_sent; // Count of packet IQ samples sent
reg [18:0] CP_iq_sent;  // Count of Cyclic Prefix IQ samples sent

assign pkt_fifo_idata  = ifft_o_result_reg; // Input data from registered IFFT output
assign pkt_fifo_ivalid = (ifft_status == OUTPUT_STARTED) ? ifft_ce_reg : 1'b0; // Valid when IFFT is enabled and started
assign pkt_fifo_oready = ((state3 == S3_L_SIG) || (state3 == S3_HT_SIG) || (state3 == S3_DATA)) && (fifo_turn == PKT_FIFO) ? result_iq_ready : 1'b0;

//////////////////////////////////////////////////////////////////////////
// Count number of [pkt/CP] IQ samples sent (FIFO Turn Logic)
//////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (reset_int) begin
        fifo_turn    <= PKT_FIFO; // Start by sending packet data first (after preamble)
        pkt_iq_sent <= 21'b0;
        CP_iq_sent  <= 19'b0;
    end else begin
        // Update counters only when handshake is valid and data is consumed
        if((result_iq_ready == 1'b1) && (result_iq_valid == 1'b1)) begin
            if(fifo_turn == PKT_FIFO) begin
                // Check if current packet IQ symbol is done and switch to CP_FIFO
                // Logic based on pkt_iq_sent[5:0] (64 samples per symbol) and pkt_iq_sent[15:8] (symbol index range check)
                if((pkt_iq_sent[5:0] == 6'b111111) && (|pkt_iq_sent[15:8] == 1'b1)) // This |pkt_iq_sent[15:8] is odd, usually a comparison to a known max value
                    fifo_turn <= CP_FIFO;
                pkt_iq_sent    <= pkt_iq_sent + 1'b1;
            end else if(fifo_turn == CP_FIFO) begin
                // Check if current CP symbol is done and switch back to PKT_FIFO
                // Logic needs to be precise about CP duration for short vs. normal GI
                if(((pkt_iq_sent < 21'd640) && (CP_iq_sent[3:0] == 4'b1111)) || ((S_GI == 1'b0) && (CP_iq_sent[3:0] == 4'b1111)) || ((S_GI == 1'b1) && (pkt_iq_sent >= 21'd640) && (CP_iq_sent[2:0] == 3'b111)))
                    fifo_turn <= PKT_FIFO;
                CP_iq_sent     <= CP_iq_sent + 1'b1;
            end
        end
    end
end

//////////////////////////////////////////////////////////////////////////
// DOT11 TX FINITE STATE MACHINE 3 (IQ sample forwarding) - CRITICAL SECTION
//////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (reset_int) begin
        preamble_addr <= 8'b0;
        phy_tx_done <= 1'b0;
        FSM3_reset <= 1'b0;
        phy_tx_started <= 1'b0; // Ensure this is also reset
        state3 <= S3_WAIT_PKT;
    end else begin
        // Default assignments to prevent X if no specific condition met,
        // and to clear one-shot signals.
        phy_tx_started <= 1'b0; // Clear unless re-asserted in a state
        phy_tx_done <= 1'b0;     // Clear unless re-asserted
        FSM3_reset <= 1'b0;      // Clear (it's a self-clearing reset by design)

        // Only allow state transitions if the output IQ interface is ready.
        // If result_iq_ready is X, (result_iq_ready == 1) will be X.
        // To prevent state3 from becoming X, we must ensure an assignment
        // in the 'else' path or default behavior is clearly defined.
        // The structure `if (...) begin ... end else begin state3 <= state3; end`
        // (implied by not assigning) is what you want if `result_iq_ready` is 0.
        // However, if `result_iq_ready` is X, this `if` condition itself becomes X,
        // causing `state3` to go X.
        // The solution is to check for a *valid* high, and default to holding.
        if (result_iq_ready == 1'b1) begin // Explicitly check for '1'
            case(state3)
            S3_WAIT_PKT: begin
                if(phy_tx_start) begin
                    preamble_addr <= 8'b0;
                    state3 <= S3_L_STF;
                end
            end

            S3_L_STF: begin
                // Legacy short preamble (160 samples, 10 * 16-sample blocks if reading from 16-bit ROM)
                // If preamble_addr increments one sample at a time, then it's 0 to 159
                if(preamble_addr < 8'd159) begin
                    preamble_addr <= preamble_addr + 1'b1;
                end else begin
                    preamble_addr <= 8'b0; // Reset for next preamble
                    state3 <= S3_L_LTF;
                end

                // Send "OPERATION STARTED" message to upper layer
                if(preamble_addr == 8'd0) begin // Assert on the first sample of L_STF
                    phy_tx_started <= 1'b1;
                end
            end

            S3_L_LTF: begin
                // Legacy long preamble (160 samples)
                if(preamble_addr < 8'd159) begin
                    preamble_addr <= preamble_addr + 1'b1;
                end else begin
                    state3 <= S3_L_SIG;
                end
            end

            S3_L_SIG: begin
                // Legacy SIGNAL (80 samples: 64 data + 16 CP)
                // Check if all L_SIG samples have been sent
                // (pkt_iq_sent and CP_iq_sent track overall packet samples from IFFT output)
                if((pkt_iq_sent == 21'd383) && (CP_iq_sent == 19'd16)) begin
                    // 160 (L-STF) + 160 (L-LTF) + 80 (L-SIG) = 400 total.
                    // pkt_iq_sent includes packet (non-CP) IQ, CP_iq_sent includes CP IQ
                    // Check your IQ counter logic, this condition must mean 400 IQ samples in total.
                    // (383+16) might be slightly off given 80-sample symbols.
                    // Assuming total samples are 400 (480-80). pkt_iq_sent starts at 0 for L-STF, L-LTF.
                    // 160 L-STF (pkt_iq_sent 0-159)
                    // 160 L-LTF (pkt_iq_sent 160-319)
                    // Then for L-SIG, it's 64 packet IQ and 16 CP IQ. So 320 + 64 = 384 for pkt_iq_sent.
                    // And 16 for CP_iq_sent. So (384-1) = 383, and (16-1) = 15?
                    // This is a common point of error for off-by-one or off-by-N.
                    // Debugging this with waveforms is key.
                    if(PKT_TYPE == LEGACY)
                        state3 <= S3_DATA;
                    else
                        state3 <= S3_HT_SIG;
                end
            end

            S3_HT_SIG: begin
                // HT SIGNAL (160 samples, two OFDM symbols: 128 data + 32 CP)
                // Check if all HT_SIG samples have been sent.
                // Assuming (160 L-STF + 160 L-LTF + 80 L-SIG) + (128 HT-SIG Data + 32 HT-SIG CP) = 560 samples total
                // Your current values are (pkt_iq_sent == 511 && CP_iq_sent == 48)
                // This means (511+1 + 48+1) = 561, close to 560.
                if((pkt_iq_sent == 21'd511) && (CP_iq_sent == 19'd48)) begin
                    preamble_addr <= 8'b0; // Reset for HT-STF
                    state3 <= S3_HT_STF;
                end
            end

            S3_HT_STF: begin
                // HT short preamble (80 samples)
                if(preamble_addr < 8'd79) begin
                    preamble_addr <= preamble_addr + 1'b1;
                end else begin
                    preamble_addr <= 8'b0; // Reset for HT-LTF
                    state3 <= S3_HT_LTF;
                end
            end

            S3_HT_LTF: begin
                // HT long preamble (80 samples)
                if(preamble_addr < 8'd79) begin
                    preamble_addr <= preamble_addr + 1'b1;
                end else begin
                    state3 <= S3_DATA;
                end
            end

            S3_DATA: begin
                // DATA field (Variable number of samples)
                // Total samples sent (pkt_iq_sent + CP_iq_sent, effectively) compared to total expected IQs
                // This sum will reach `nof_iq2send` as the last samples are sent.
                // The `-2` suggests it's detecting done two cycles before actual last output.
                if(((pkt_iq_sent + {2'b00, CP_iq_sent}) == nof_iq2send-21'd2)) begin
                    phy_tx_done <= 1'b1;   // Assert tx done
                    FSM3_reset <= 1'b1;    // Assert internal reset for FSM3
                end
            end

            default: begin // Catch any undefined state (shouldn't happen with proper FSM design)
                state3 <= S3_WAIT_PKT;
            end
            endcase
        end
        // else if result_iq_ready is 0 or X, state3 will hold its current value.
        // This is typically desired for output-gated FSMs.
        // If result_iq_ready can go X, this is where it would propagate,
        // but now the `if (result_iq_ready == 1'b1)` explicitly checks for '1'.
        // If it's `X`, the `if` condition is `X`, and no assignment is made,
        // thus `state3` holds its last valid value, preventing `X` propagation into `state3`.
    end
end

// These were already combinational assignments, correctly.
assign result_iq_valid = (state3 == S3_L_STF || state3 == S3_L_LTF) ? (preamble_addr >= 8'd0 && preamble_addr < 8'd160) :
                         ((state3 == S3_L_SIG || state3 == S3_HT_SIG) && pkt_fifo_ovalid == 1'b1 && fifo_turn == PKT_FIFO) ? 1'b1 : // result_iq_ready removed here, as valid should indicate readiness of data irrespective of sink's readiness
                         (state3 >= S3_HT_STF && (pkt_fifo_ovalid == 1'b1 || CP_fifo_ovalid == 1'b1));
                         // The receiver's readiness (`result_iq_ready` input) controls the FSM, not the validity of *this* output.

assign result_i = (state3 == S3_L_STF || state3 == S3_L_LTF) ? (state3 == S3_L_STF ? l_stf[31:16] : l_ltf[31:16]) :
                  (fifo_turn == CP_FIFO ? CP_fifo_odata[31:16] : pkt_fifo_odata[31:16]);
assign result_q = (state3 == S3_L_STF || state3 == S3_L_LTF) ? (state3 == S3_L_STF ? l_stf[15:0] : l_ltf[15:0]) :
                  (fifo_turn == CP_FIFO ? CP_fifo_odata[15:0] : pkt_fifo_odata[15:0]);

endmodule
