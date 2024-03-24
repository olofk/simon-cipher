//
// lint options for Verilator
//
/* verilator lint_off DECLFILENAME */

//------------------ SIMON DEFINES -------------------------------
`define true  1'b1
`define false 1'b0

// these are the crypto opterations that the SIMON_CORE module supports
typedef enum logic [2:0] {
  SIMON_IDLE       = 3'b000,
  SIMON_KEYEXPAND  = 3'b001,
  SIMON_ENCRYPT    = 3'b010,
  SIMON_DECRYPT    = 3'b011,
  SIMON_ENCRYPT_CL = 3'b100,
  SIMON_DECRYPT_CL = 3'b101
} simon_op_e /*verilator public*/;

// 
// SIMON_CORE: This is a test driver module used by tb_simon_core.cpp
//
module simon_core #(
   parameter int unsigned SIMON_KEY_W,            // SIMON key size (in bits), 64 and 128-bits are supported
   parameter int unsigned SIMON_DATA_W,           // SIMON data size (in bits), 32, 64, and 128-bits are supported
   parameter bit [6:0] SIMON_ROUNDS,              // SIMON rounds to execute during encryption/decryption
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE     // SIMON rounds to execute each cycle, leading to pipelined implementations
) (
    input  logic        clk,                      // system clock signal
    input  logic        rst,                      // system reset signal, asserted high
    input  simon_op_e   op_i,                     // INPUT: crypto operation to execute
    input  logic        key_valid_i,              // INPUT: assert this signal to transfer a key value to the SIMON core
    input  logic [7:0]  key_i [0:(SIMON_KEY_W/8)-1], // INPUT: SIMON key to expand
    input  logic        data_valid_i,             // INPUT: assert this signal to transfer a data value to the SIMON core
    input  logic [SIMON_DATA_W-1:0] data_i,       // INPUT: SIMON data input
    output logic        data_valid_o,             // OUTPUT: this signal is asserted to indicate that an output valid is available
    output logic [SIMON_DATA_W-1:0] data_o,       // OUTPUT: SIMON core data output
    output logic        ready_o                   // OUTPUT: asserted when the SIMON core is ready for a new request

);
  logic [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1];
  logic keytab_valid_o, enc_valid_o, dec_valid_o;
  logic keyexpand_ready_o, enc_ready_o, dec_ready_o;
  logic [SIMON_DATA_W-1:0] enc_data_o;
  logic [SIMON_DATA_W-1:0] dec_data_o;
  logic [SIMON_DATA_W-1:0] enc_cl_data_o;
  logic [SIMON_DATA_W-1:0] dec_cl_data_o;

  simon_core_keyexpand #(
  .SIMON_KEY_W            (SIMON_KEY_W),
  .SIMON_DATA_W           (SIMON_DATA_W),
  .SIMON_ROUNDS           (SIMON_ROUNDS)
  ) keyexpand_inst (
   .clk               (clk),
   .rst               (rst),
   .key_valid_i       (key_valid_i),
   .key_i             (key_i),
   .keytab_valid_o    (keytab_valid_o),
   .keytab_o          (keytab),
   .ready_o           (keyexpand_ready_o)
  );

  simon_cl_encryptor #(
   .SIMON_DATA_W          (SIMON_DATA_W),
   .SIMON_ROUNDS          (SIMON_ROUNDS)
  ) cl_encryptor_inst (
   .data_i                (data_i),
   .keytab_i              (keytab),
   .data_o                (enc_cl_data_o)
  );

  simon_core_encryptor #(
  .SIMON_DATA_W           (SIMON_DATA_W),
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
  ) encryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .data_valid_i      (data_valid_i),
   .data_i            (data_i),
   .keytab_i          (keytab),
   .data_valid_o      (enc_valid_o),
   .data_o            (enc_data_o),
   .ready_o           (enc_ready_o)
  );

  simon_cl_decryptor #(
   .SIMON_DATA_W          (SIMON_DATA_W),
   .SIMON_ROUNDS          (SIMON_ROUNDS)
  ) cl_decryptor_inst (
   .data_i                (data_i),
   .keytab_i              (keytab),
   .data_o                (dec_cl_data_o)
  );

  simon_core_decryptor #(
  .SIMON_DATA_W           (SIMON_DATA_W),
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
  ) decryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .data_valid_i      (data_valid_i),
   .data_i            (data_i),
   .keytab_i          (keytab),
   .data_valid_o      (dec_valid_o),
   .data_o            (dec_data_o),
   .ready_o           (dec_ready_o)
  );

  assign data_valid_o = keytab_valid_o | enc_valid_o | dec_valid_o;
  assign ready_o = keyexpand_ready_o & enc_ready_o & dec_ready_o;

  always_comb begin
    unique case (op_i)
      SIMON_IDLE,
      SIMON_KEYEXPAND:    data_o = 0;
      SIMON_ENCRYPT:      data_o = enc_data_o;
      SIMON_DECRYPT:      data_o = dec_data_o;
      SIMON_ENCRYPT_CL:   data_o = enc_cl_data_o;
      SIMON_DECRYPT_CL:   data_o = dec_cl_data_o;
      default:            data_o = 0;
    endcase
  end

endmodule;

//
// SIMON module key expansion: given a "key_i" value, that is latched on
// "key_valid_i", this module will perform key expansion that is copied to
// "keytab_o" memory, at which point "keytab_valid_o" indicates the keytable
// is ready, "ready_o" indicates when the module is available for another
// request
//
module simon_core_keyexpand #(
   parameter int unsigned SIMON_KEY_W,                // SIMON key size (in bits), 64 and 128-bits are supported
   parameter int unsigned SIMON_DATA_W,               // SIMON data size (in bits), 32, 64, and 128-bits are supported
   parameter bit [6:0] SIMON_ROUNDS                   // SIMON rounds to execute during encryption/decryption
) (
   input  logic       clk,                            // system clock signal
   input  logic       rst,                            // system reset signal, asserted high
   input  logic       key_valid_i,                    // INPUT: assert this signal to transfer a key value to the SIMON core
   input  logic [7:0] key_i [0:(SIMON_KEY_W/8)-1],    // INPUT: SIMON key to expand
   output logic       keytab_valid_o,                 // OUTPUT: asserted when the keytab has been fully written
   output logic [(SIMON_DATA_W/2)-1:0] keytab_o[0:SIMON_ROUNDS - 1], // OUTPUT: key tab external storage to write expanded keytab
   output logic       ready_o                         // OUTPUT: asserted when the SIMON core is ready for a new request
);

  localparam int unsigned SIMON_ROUNDS_LOG2 = $clog2(SIMON_ROUNDS);
  localparam int unsigned SIMON_WORDS_PER_KEY = (SIMON_KEY_W/SIMON_DATA_W) * 2;

  logic [(SIMON_DATA_W/2)-1:0] tmp0;
  logic [(SIMON_DATA_W/2)-1:0] tmp1;
  logic [(SIMON_DATA_W/2)-1:0] tmp1a;
  logic [(SIMON_DATA_W/2)-1:0] tmp2;
  logic ready_q;
  logic [SIMON_ROUNDS_LOG2-1:0] current_iter_q;
  logic keytab_valid_q;
  logic [(SIMON_DATA_W/2)-1:0] key_words[0:SIMON_ROUNDS - 1];

  assign ready_o = ready_q;
  assign keytab_valid_o = keytab_valid_q;

  /*
  k[1]..k[0] = key words
  ------------------------- key expansion -------------------------
               for i = 2..67
      assign tmp0 = k[i-1];
      assign tmp1 = {tmp0[2:0], tmp0[63:3]};
      assign tmp2 =  tmp1 ^ {tmp1[0]. tmp1[63:1]};
      k[i] <= 64'hFFFFFFFFFFFFFFFC ^ k[i-2] ^ tmp ^ {63'h0, z[i-2]}
  end for
  */
  assign tmp0 = key_words[current_iter_q-1];
  assign tmp1 = {tmp0[2:0], tmp0[(SIMON_DATA_W/2)-1:3]};
  assign tmp1a = tmp1 ^ ((SIMON_WORDS_PER_KEY == 4) ? key_words[current_iter_q-3] : 0);
  assign tmp2 =  tmp1a ^ {tmp1a[0], tmp1a[(SIMON_DATA_W/2)-1:1]};
  logic [(SIMON_DATA_W/2)-1:0] key_words_in0, key_words_in1, key_words_in2, key_words_in3;
  logic [65:0] z;

  generate
    if (SIMON_DATA_W == 32) begin : genblk1
      assign key_words_in0 = {key_i[1], key_i[0]};
      assign key_words_in1 = {key_i[3], key_i[2]};
      assign key_words_in2 = {key_i[5], key_i[4]};
      assign key_words_in3 = {key_i[7], key_i[6]};
      assign z = 66'h19c3_522f_b386_a45f;
    end
    else if (SIMON_DATA_W == 64) begin : genblk2
      assign key_words_in0 = {key_i[3], key_i[2], key_i[1], key_i[0]};
      assign key_words_in1 = {key_i[7], key_i[6], key_i[5], key_i[4]};
      assign key_words_in2 = {key_i[11], key_i[10], key_i[9], key_i[8]};
      assign key_words_in3 = {key_i[15], key_i[14], key_i[13], key_i[12]};
      assign z = 66'h7c2c_e512_07a6_35db;
    end
    else if (SIMON_DATA_W == 128) begin : genblk3
      assign key_words_in0 = {key_i[7], key_i[6], key_i[5], key_i[4], key_i[3], key_i[2], key_i[1], key_i[0]};
      assign key_words_in1 = {key_i[15], key_i[14], key_i[13], key_i[12], key_i[11], key_i[10], key_i[9], key_i[8]};
      assign key_words_in2 = 0;
      assign key_words_in3 = 0;
      assign z = 66'b010111_0011011010_0111111000_1000010100_0110010010_1100000011_1011110101;
    end
    else begin : genfail
      $fatal("SIMON_* parameters are not set correctly.");
    end
  endgenerate

  always_ff @(posedge clk) begin

    // STATE: handle reset
    if (rst) begin
      ready_q <= `true;
      keytab_valid_q <= `false;
      current_iter_q <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
      key_words <= '{default:'0};
    end
 
    // STATE: new request
    else if (ready_q && key_valid_i) begin
      ready_q <= `false;
      current_iter_q <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
      // Set first two elements of key table to original key
      key_words[0] <= key_words_in0;
      key_words[1] <= key_words_in1;
      key_words[2] <= key_words_in2;
      key_words[3] <= key_words_in3;
`ifdef notdef
      foreach(key_i[q]) $display("%t %m key_i[%d]=0x%x", $time, q, key_i[q]);
`endif /* notdef */
    end

    // STATE: ongoing key expansion and not the last iteration
    else if (!ready_q && !keytab_valid_q && current_iter_q != SIMON_ROUNDS[SIMON_ROUNDS_LOG2-1:0]) begin
      key_words[current_iter_q] <= (SIMON_DATA_W/2)'(64'h0 - 4)
                                    ^ key_words[current_iter_q-((SIMON_DATA_W == 128) ? 2 : 4)]
                                    ^ tmp2
                                    ^ {{((SIMON_DATA_W/2)-1){1'b0}}, z[current_iter_q-((SIMON_DATA_W == 128) ? 2 : 4)]};
      current_iter_q <= current_iter_q + 1;
    end

    // STATE: ongoing key expansion and the LAST iteration
    else if (!ready_q && !keytab_valid_q && current_iter_q == SIMON_ROUNDS[SIMON_ROUNDS_LOG2-1:0]) begin
      keytab_valid_q <= `true;
      keytab_o <= key_words;
`ifdef notdef
      foreach(key_words[q]) $display("%t %m key_words[%d]=0x%x", $time, q, key_words[q]);
`endif /* notdef */
    end

    // STATE: output has been delivered and we can reset everything
    else if (!ready_q && keytab_valid_q) begin
      ready_q <= `true;
      keytab_valid_q <= `false;
      current_iter_q <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
    end
  
  end  
endmodule

//
// SIMON module combinational logic encryptor: given a "keytab_i" key table,
// "data_i" is encrypted with the SIMON cipher to "data_o" using pure
// combinational logic, the caller is responsible for latching the results
//
module simon_cl_encryptor #(
   parameter int unsigned SIMON_DATA_W,           // SIMON data size (in bits), 32, 64, and 128-bits are supported
   parameter bit [6:0] SIMON_ROUNDS               // SIMON rounds to execute during encryption/decryption
) (
   input  logic [SIMON_DATA_W-1:0] data_i,        // INPUT: SIMON data input to encrypt`
   input  logic [(SIMON_DATA_W/2)-1:0] keytab_i[0:SIMON_ROUNDS - 1], // INPUT: previously expanded SIMON key table
   output logic [SIMON_DATA_W-1:0] data_o         // OUTPUT: OUTPUT: SIMON core data output ciphertext
);
  typedef logic [$clog2(SIMON_ROUNDS+1)-1:0] xy_idx_t;
  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS]  /*verilator split_var*/;

  genvar i;
  generate
    assign x_words[0] = data_i[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
    assign y_words[0] = data_i[(SIMON_DATA_W/2)-1:0];

    for(i=0; i < SIMON_ROUNDS; i++) begin : gencipher
      // Shift, AND, XOR ops
      // assign temp[i] = ((((x_words[i] << 1) | (x_words[i]
      //                       >> (`WORD_SIZE - 1))) & ((x_words[i] << 8) | (x_words[i]
      //                       >> (`WORD_SIZE - 8))))  ^ y_words[i] ^ ((x_words[i] << 2)
      //                       | (x_words[i] >> (`WORD_SIZE - 2))));
      assign temp[i] = (({x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]}
                         & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]})
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]});
      // cross the results
      assign y_words[i + 1] = x_words[i];
      // XOR with round key
      assign x_words[i + 1] = temp[i] ^ keytab_i[i];
    end
  endgenerate

  assign data_o = {x_words[xy_idx_t'(SIMON_ROUNDS)], y_words[xy_idx_t'(SIMON_ROUNDS)]};

endmodule

module simon_core_encryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE
) (
   input  logic        clk,
   input  logic        rst,
   input  logic        data_valid_i,
   input  logic [SIMON_DATA_W-1:0] data_i,
   input  logic [(SIMON_DATA_W/2)-1:0] keytab_i[0:SIMON_ROUNDS - 1],
   output logic        data_valid_o,
   output logic [SIMON_DATA_W-1:0] data_o,
   output logic        ready_o
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] y_ff;
  logic [(SIMON_DATA_W/2)-1:0] x_ff;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic ready_q;
  logic [SIMON_DATA_W-1:0] data_q;
  logic [6:0] roundCount_q;
  logic data_valid_q;

  assign data_valid_o  = data_valid_q;
  assign data_o = data_q;
  assign ready_o = ready_q;

  genvar i;
  generate
    assign x_words[0] = x_ff;
    assign y_words[0] = y_ff;

    for(i=0; i < SIMON_ROUNDS_PER_CYCLE; i++) begin : gencipher
      // Shift, AND, XOR ops
      // assign temp[i] = ((((x_words[i] << 1) | (x_words[i] 
      //                       >> (`WORD_SIZE - 1))) & ((x_words[i] << 8) | (x_words[i]
      //                       >> (`WORD_SIZE - 8))))  ^ y_words[i] ^ ((x_words[i] << 2) 
      //                       | (x_words[i] >> (`WORD_SIZE - 2))));
      assign temp[i] = (({x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]}
                         & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]})
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]});
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      assign x_words[i + 1] = temp[i] ^ keytab_i[roundCount_q + i];
    end
  endgenerate

  always_ff @(posedge clk) begin

    // STATE: handle reset
    if (rst) begin
      ready_q <= `true;
      data_valid_q  <= `false;
      roundCount_q <= 0;
      y_ff <= 0;
      x_ff <= 0;
      data_q <= 0;
    end

    // STATE: new request, so latch input
    else if (ready_q && data_valid_i) begin
      ready_q <= `false;
      x_ff <= data_i[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
      y_ff <= data_i[(SIMON_DATA_W/2)-1:0];
      roundCount_q <= 0;
    end

    // STATE: ongoing key expansion and not the last iteration
    else if (!ready_q && !data_valid_q) begin

      // SUBSTATE: not the last iteration, still have work to do -- perform an intermediate latch now
      /* verilator lint_off UNSIGNED */
      if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount_q < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE)
          || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount_q < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin
      /* verilator lint_on UNSIGNED */
        roundCount_q <= roundCount_q + SIMON_ROUNDS_PER_CYCLE;
        y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
        x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
      end

      // SUBSTATE: finishing up the short tail; latch from tail and set output to valid
      else if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
        data_valid_q <= `true;
        data_q <= {x_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], y_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]};
        // cleanup internal state
        roundCount_q <= 0;
        y_ff <= 0; 
        x_ff <= 0; 
      end

      // SUBSTATE: finishing up with no perfect-multiple tail; latch from body and set output to valid
      else if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) begin
        data_valid_q <= `true;
        data_q <= {x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)], y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)]};
        // cleanup internal state
        roundCount_q <= 0;
        y_ff <= 0; 
        x_ff <= 0; 
      end

    end

    // STATE: output has been delivered and we can reset everything
    else if (!ready_q && data_valid_q) begin
      // output has been latched and we can reset everything
      ready_q <= `true;
      data_valid_q  <= `false;
      roundCount_q <= 0;
      y_ff <= 0;
      x_ff <= 0;
    end

  end
endmodule

module simon_cl_decryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS
) (
   input  logic [SIMON_DATA_W-1:0] data_i,
   input  logic [(SIMON_DATA_W/2)-1:0] keytab_i[0:SIMON_ROUNDS - 1],
   output logic [SIMON_DATA_W-1:0] data_o
);
  typedef logic [$clog2(SIMON_ROUNDS+1)-1:0] xy_idx_t;
  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS]  /*verilator split_var*/;

  genvar i;
  generate
    assign x_words[0] = data_i[(SIMON_DATA_W/2)-1:0];
    assign y_words[0] = data_i[SIMON_DATA_W-1:(SIMON_DATA_W/2)];

    for(i=0; i < SIMON_ROUNDS; i++) begin : gencipher
      // Shift, AND, XOR ops
      // assign temp[i] = ((((x_words[i] << 1) | (x_words[i]
      //                       >> (`WORD_SIZE - 1))) & ((x_words[i] << 8) | (x_words[i]
      //                       >> (`WORD_SIZE - 8))))  ^ y_words[i] ^ ((x_words[i] << 2)
      //                       | (x_words[i] >> (`WORD_SIZE - 2))));
      assign temp[i] = (({x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]}
                         & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]})
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]});
      // cross the results
      assign y_words[i + 1] = x_words[i];
      // XOR with round key
      assign x_words[i + 1] = temp[i] ^ keytab_i[(SIMON_ROUNDS - i - 1)];
    end
  endgenerate

  assign data_o ={y_words[xy_idx_t'(SIMON_ROUNDS)], x_words[xy_idx_t'(SIMON_ROUNDS)]};

endmodule

module simon_core_decryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE
) (
   input  logic  clk,
   input  logic  rst,
   input  logic  data_valid_i,
   input  logic  [SIMON_DATA_W-1:0] data_i,
   input  logic  [(SIMON_DATA_W/2)-1:0] keytab_i[0:SIMON_ROUNDS - 1],
   output logic  data_valid_o,
   output logic  [SIMON_DATA_W-1:0] data_o,
   output logic  ready_o
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] y_ff;
  logic [(SIMON_DATA_W/2)-1:0] x_ff;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic ready_q;
  logic [SIMON_DATA_W-1:0] data_q;
  logic [6:0] roundCount_q;
  logic data_valid_q;

  assign data_valid_o = data_valid_q;
  assign data_o = data_q;
  assign ready_o = ready_q;

  genvar i;
  generate
    assign x_words[0] = x_ff;
    assign y_words[0] = y_ff;

    for(i=0; i < SIMON_ROUNDS_PER_CYCLE; i++) begin : gencipher
      // Shift, AND, XOR ops
      // TMA: assign temp[i] = ((((x_words[i] << 1) | (x_words[i] 
      //                       >> (`WORD_SIZE - 1))) & ((x_words[i] << 8) | (x_words[i]
      //                       >> (`WORD_SIZE - 8))))  ^ y_words[i] ^ ((x_words[i] << 2) 
      //                       | (x_words[i] >> (`WORD_SIZE - 2))));
      assign temp[i] = (({x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]}
                         & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]})
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]});
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      assign x_words[i + 1] = temp[i] ^ keytab_i[(SIMON_ROUNDS - i - 1) - roundCount_q];
    end
  endgenerate

  always_ff @(posedge clk) begin
          
    // STATE: handle reset
    if (rst) begin
      ready_q <= `true;
      data_valid_q <= `false;
      roundCount_q <= 0;
      y_ff <= 0;
      x_ff <= 0;
      data_q <= 0;
    end

    // STATE: new request, so latch input
    else if (ready_q && data_valid_i) begin
      ready_q <= `false;
      y_ff <= data_i[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
      x_ff <= data_i[(SIMON_DATA_W/2)-1:0];
      roundCount_q <= 0;
    end

    // STATE: ongoing key expansion and not the last iteration
    else if (!ready_q && !data_valid_q) begin

      // SUBSTATE: not the last iteration, still have work to do -- perform an intermediate latch now
      /* verilator lint_off UNSIGNED */
      if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount_q < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE)
          || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount_q < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin
      /* verilator lint_on UNSIGNED */
        roundCount_q <= roundCount_q + SIMON_ROUNDS_PER_CYCLE;
        y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
        x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
      end

      // SUBSTATE: finishing up the short tail; latch from tail and set output to valid
      else if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
        // Finishing up the tail; latch from tail and set output to valid
        data_valid_q <= `true;
        data_q <= {y_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], x_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]};
        // cleanup internal state
        roundCount_q <= 0;
        y_ff <= 0;
        x_ff <= 0;
      end

      // SUBSTATE: finishing up with no perfect-multiple tail; latch from body and set output to valid
      else if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) begin
        data_valid_q <= `true;
        data_q <= {y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)], x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)]};
        // cleanup internal state
        roundCount_q <= 0;
        y_ff <= 0;
        x_ff <= 0;
      end

    end

    // STATE: output has been delivered and we can reset everything
    else if (!ready_q && data_valid_q) begin
      ready_q <= `true;
      data_valid_q <= `false;
      roundCount_q <= 0;
      y_ff <= 0;
      x_ff <= 0;
    end

  end
endmodule

