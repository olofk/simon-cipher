//
// lint options for Verilator
//
/* verilator lint_off DECLFILENAME */

//------------------ SIMON DEFINES -------------------------------
`define true  1'b1
`define false 1'b0

typedef enum logic [2:0] {
  SIMON_IDLE       = 3'b000,
  SIMON_KEYEXPAND  = 3'b001,
  SIMON_ENCRYPT    = 3'b010,
  SIMON_DECRYPT    = 3'b011,
  SIMON_ENCRYPT_CL = 3'b100,
  SIMON_DECRYPT_CL = 3'b101
} simon_op_e /*verilator public*/;

module simon_core #(
   parameter int unsigned SIMON_KEY_W,
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE
) (
    input  logic        clk, rst,
    // input ports
    input  simon_op_e   op_i,
    input  logic        key_valid_i,
    input  logic [7:0]  key_i [0:(SIMON_KEY_W/8)-1],
    input  logic        data_valid_i,
    input  logic [SIMON_DATA_W-1:0] data_i,

    // output ports
    output logic        ready_o,
    output logic        data_valid_o,
    output logic [SIMON_DATA_W-1:0] data_o

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
   .key_in            (key_i),
   .keytab            (keytab),
   .keytab_valid_o    (keytab_valid_o),
   .ready_o           (keyexpand_ready_o)
  );

  simon_cl_encryptor #(
   .SIMON_DATA_W          (SIMON_DATA_W),
   .SIMON_ROUNDS          (SIMON_ROUNDS)
  ) cl_encryptor_inst (
   .enc_in                (data_i),
   .keytab                (keytab),
   .enc_out               (enc_cl_data_o)
  );

  simon_core_encryptor #(
  .SIMON_DATA_W           (SIMON_DATA_W),
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
  ) encryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .data_valid_i      (data_valid_i),
   .enc_in            (data_i),
   .enc_out           (enc_data_o),
   .keytab            (keytab),
   .enc_valid_o       (enc_valid_o),
   .ready_o           (enc_ready_o)
  );

  simon_cl_decryptor #(
   .SIMON_DATA_W          (SIMON_DATA_W),
   .SIMON_ROUNDS          (SIMON_ROUNDS)
  ) cl_decryptor_inst (
   .dec_in                (data_i),
   .keytab                (keytab),
   .dec_out               (dec_cl_data_o)
  );

  simon_core_decryptor #(
  .SIMON_DATA_W           (SIMON_DATA_W),
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
  ) decryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .data_valid_i      (data_valid_i),
   .dec_in            (data_i),
   .dec_out           (dec_data_o),
   .keytab            (keytab),
   .dec_valid_o       (dec_valid_o),
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

module simon_core_keyexpand #(
   parameter int unsigned SIMON_KEY_W,
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS
) (
   input  logic       clk,
   input  logic       rst,
   input  logic       key_valid_i,
   input  logic [7:0] key_in [0:(SIMON_KEY_W/8)-1],
   output logic       ready_o,
   output logic [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1],
   output logic       keytab_valid_o
);

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

  localparam int unsigned SIMON_ROUNDS_LOG2 = $clog2(SIMON_ROUNDS);
  localparam int unsigned SIMON_WORDS_PER_KEY = (SIMON_KEY_W/SIMON_DATA_W) * 2;

  logic [(SIMON_DATA_W/2)-1:0] tmp0;
  logic [(SIMON_DATA_W/2)-1:0] tmp1;
  logic [(SIMON_DATA_W/2)-1:0] tmp1a;
  logic [(SIMON_DATA_W/2)-1:0] tmp2;
  logic           busy;
  logic [SIMON_ROUNDS_LOG2-1:0]     current_iter, current_iter_minus1, next_iter;
  logic           local_keytab_valid_o;
  logic [(SIMON_DATA_W/2)-1:0] key_words[0:SIMON_ROUNDS - 1];

  assign ready_o = !busy;

  assign keytab_valid_o = local_keytab_valid_o;

  assign tmp0 = key_words[current_iter_minus1];
  assign tmp1 = {tmp0[2:0], tmp0[(SIMON_DATA_W/2)-1:3]};
  assign tmp1a = tmp1 ^ ((SIMON_WORDS_PER_KEY == 4) ? key_words[current_iter-3] : 0);
  assign tmp2 =  tmp1a ^ {tmp1a[0], tmp1a[(SIMON_DATA_W/2)-1:1]};
  assign next_iter = current_iter + 1;
  logic [(SIMON_DATA_W/2)-1:0] key_words_in0, key_words_in1, key_words_in2, key_words_in3;
  logic [65:0] z;

  generate
    if (SIMON_DATA_W == 32) begin : genblk1
      assign key_words_in0 = {key_in[1], key_in[0]};
      assign key_words_in1 = {key_in[3], key_in[2]};
      assign key_words_in2 = {key_in[5], key_in[4]};
      assign key_words_in3 = {key_in[7], key_in[6]};
      assign z = 66'h19c3_522f_b386_a45f;
    end
    else if (SIMON_DATA_W == 64) begin : genblk2
      assign key_words_in0 = {key_in[3], key_in[2], key_in[1], key_in[0]};
      assign key_words_in1 = {key_in[7], key_in[6], key_in[5], key_in[4]};
      assign key_words_in2 = {key_in[11], key_in[10], key_in[9], key_in[8]};
      assign key_words_in3 = {key_in[15], key_in[14], key_in[13], key_in[12]};
      assign z = 66'h7c2c_e512_07a6_35db;
    end
    else if (SIMON_DATA_W == 128) begin : genblk3
      assign key_words_in0 = {key_in[7], key_in[6], key_in[5], key_in[4], key_in[3], key_in[2], key_in[1], key_in[0]};
      assign key_words_in1 = {key_in[15], key_in[14], key_in[13], key_in[12], key_in[11], key_in[10], key_in[9], key_in[8]};
      assign key_words_in2 = 0;
      assign key_words_in3 = 0;
      assign z = 66'b010111_0011011010_0111111000_1000010100_0110010010_1100000011_1011110101;
    end
    else begin : genfail
      $fatal("SIMON_* parameters are not set correctly.");
    end
  endgenerate

  always_ff @(posedge clk) begin
`ifdef notdef
    if (busy) begin
      $display("%t %m key_expander.local_keytab_valid_o=%d", $time, local_keytab_valid_o);
      $display("%t %m key_expander.current_iter=%d", $time, current_iter);
      $display("%t %m key_expander.current_iter_minus1=%d", $time, current_iter_minus1);
    end
`endif /* notdef */
    if (rst) begin
      busy <= `false;
      local_keytab_valid_o <= `false;
      current_iter <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
      current_iter_minus1 <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0]-1;
      key_words <= '{default:'0};
      keytab <= '{default:'0};
    end
    else begin
      // In the middle of doing a key expansion
      if (busy) begin
        if (local_keytab_valid_o) begin
            // Output has been latched and we can reset everything
            busy <= `false;
            local_keytab_valid_o <= `false;
            current_iter <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
            current_iter_minus1 <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0]-1;
        end
        // Not done yet
        else begin 
          // On last round
          if (current_iter == SIMON_ROUNDS[SIMON_ROUNDS_LOG2-1:0]) begin
            local_keytab_valid_o <= `true;
            keytab <= key_words;
`ifdef notdef
            foreach(key_words[q]) $display("%t %m key_words[%d]=0x%x", $time, q, key_words[q]);
`endif /* notdef */
          end
          // Not on last round yet
          else begin
            key_words[current_iter] <= (SIMON_DATA_W/2)'(64'h0 - 4)
                                       ^ key_words[current_iter-((SIMON_DATA_W == 128) ? 2 : 4)]
                                       ^ tmp2
                                       ^ {{((SIMON_DATA_W/2)-1){1'b0}}, z[current_iter-((SIMON_DATA_W == 128) ? 2 : 4)]};
            current_iter <= next_iter;
            current_iter_minus1 <= next_iter - 1;
          end
        end
      end
      // Idle
      else begin
        // Can handle incoming request
        if (key_valid_i) begin
          current_iter <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
          current_iter_minus1 <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0]-1;
          busy <= `true;
          // Set first two elements of key table to original key
          // Compiler wouldn't let me do this a nicer way
          //key_words[0:1] <= {key_in[0:7], key_in[8:15]};
          key_words[0] <= key_words_in0;
          key_words[1] <= key_words_in1;
          key_words[2] <= key_words_in2;
          key_words[3] <= key_words_in3;
`ifdef notdef
          foreach(key_in[q]) $display("%t %m key_in[%d]=0x%x", $time, q, key_in[q]);
`endif /* notdef */
        end
        // Idle and no incoming request
        else begin
          current_iter <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0];
          current_iter_minus1 <= SIMON_WORDS_PER_KEY[SIMON_ROUNDS_LOG2-1:0]-1;
          busy <= `false;
        end
      end
    end
  end  
endmodule

module simon_cl_encryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS
) (
   input  logic [SIMON_DATA_W-1:0] enc_in,
   input  logic [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1],
   output logic [SIMON_DATA_W-1:0] enc_out
);
  typedef logic [$clog2(SIMON_ROUNDS+1)-1:0] xy_idx_t;
  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS]  /*verilator split_var*/;

  genvar i;
  generate

    assign x_words[0] = enc_in[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
    assign y_words[0] = enc_in[(SIMON_DATA_W/2)-1:0];

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
      assign x_words[i + 1] = temp[i] ^ keytab[i];
    end
  endgenerate

  assign enc_out = {x_words[xy_idx_t'(SIMON_ROUNDS)], y_words[xy_idx_t'(SIMON_ROUNDS)]};

endmodule

module simon_core_encryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE
) (
   input  logic        clk,
   input  logic        rst,
   input  logic        data_valid_i,
   input  logic [SIMON_DATA_W-1:0] enc_in,
   input  logic [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1],
   output logic        ready_o,
   output logic [SIMON_DATA_W-1:0] enc_out,
   output logic        enc_valid_o 
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] y_ff;
  logic [(SIMON_DATA_W/2)-1:0] x_ff;
  logic busy;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;

  assign ready_o = !busy;

  logic [6:0] roundCount;
  logic local_enc_valid_o ;

  assign enc_valid_o  = local_enc_valid_o ;

`ifdef notdef
  always_comb begin
    $display("enc input: %h", enc_in);
    $write("x_words[%d]: %h, ", 0, x_words[0]);
    $write("y_words[%d]: %h, ", 0, y_words[0]);

    $display("rst: %h", rst);
    $display("data_valid_i: %h", data_valid_i);
    $display("busy: %h", busy);
    $display("x_ff: %h", x_ff);
    $display("y_ff: %h", y_ff);
    $display("enc output: %h", enc_out);
    $display("output valid: %b", local_enc_valid_o );
    $display("Done: %b", done);
    $display("roundCount: %d", roundCount);
    //$display("cycleCount: %d", cycleCount);
  end
`endif /* notdef */
  
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

      assign temp[i] = (( {x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
                       );
      
      // Calculate the cycle count
      //assign cycleCount = (i == `SIMON_ROUNDS_PER_CYCLE - 1) ? (cycleCount + 1) : cycleCount;  
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      assign x_words[i + 1] = temp[i] ^ keytab[roundCount + i];
       
`ifdef notdef
      always_comb begin
        $write("x_words[%d]: %h, ", i + 1, x_words[i + 1]);
        $write("y_words[%d]: %h, ", i + 1, y_words[i + 1]);
        $display("temp[%d]: %h", i + 1, temp[i + 1]);
      end
`endif /* notdef */
    end
  endgenerate

`ifdef notdef
  initial begin
    $monitor("%t %m rst=%d", $time, rst);
    $monitor("%t %m local_enc_valid_o =%d", $time, local_enc_valid_o );
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    $strobe("%t %m rst=%d", $time, rst);
    $strobe("%t %m local_enc_valid_o =%d", $time, local_enc_valid_o );
  end
`endif /* notdef */

  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= `false;
      local_enc_valid_o  <= `false;
      roundCount <= 0;
      y_ff <= 0;
      x_ff <= 0;
      enc_out <= 0;
    end
    else begin
      //cycleCount <= cycleCount + 1;
      if (busy) begin
        if (local_enc_valid_o ) begin
          // Output has been latched and we can reset everything
          busy <= `false;
          local_enc_valid_o  <= `false;
          roundCount <= 0;
          y_ff <= 0;
          x_ff <= 0;
        end
        else begin
          /* verilator lint_off UNSIGNED */
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin /* verilator lint_on UNSIGNED */
              
            // In body, still have work to do -- perform an intermediate latch now
            busy <= busy;
            roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE;
            y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
            x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
          end
          else begin
            if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
              // Finishing up the tail; latch from tail and set output to valid
              busy <= busy;
              local_enc_valid_o  <= `true;
              roundCount <= roundCount + (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE);
              y_ff <= y_ff; // Don't care
              x_ff <= x_ff; // Don't care
              enc_out <= {x_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], y_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]};
`ifdef SIMON_DEBUG
              $display("%t ++++++ Simon ENC out (tail) ++++++", $time);
              $display("%t %m simon_enc.enc_out=0x%x", $time,
                      {x_words[(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], y_words[(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]});
              $display("%t %m simon_enc.roundCount=%d", $time, roundCount + (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE));
              $display("%t ------ Simon ENC out (tail) ------", $time);
`endif /* SIMON_DEBUG */
            end
            else begin
              // Finishing up with no tail; latch from body and set output to valid
              busy <= busy;
              local_enc_valid_o  <= `true;
              roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE; 
              y_ff <= y_ff; // Don't care
              x_ff <= x_ff; // Don't care
              enc_out <= {x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)], y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)]};
`ifdef SIMON_DEBUG
              $display("%t ++++++ Simon ENC out (no tail) ++++++", $time);
              $display("%t %m simon_enc.enc_out=0x%x", $time,
                       {x_words[SIMON_ROUNDS_PER_CYCLE], y_words[SIMON_ROUNDS_PER_CYCLE]});
              $display("%t %m simon_enc.roundCount=%d", $time, roundCount + SIMON_ROUNDS_PER_CYCLE);
              $display("%t ------ Simon ENC out (no tail) ------", $time);
`endif /* SIMON_DEBUG */
            end
          end
        end
      end
      else begin
        if (data_valid_i) begin
          // We're available and a request is being made -- latch input
          busy <= `true;
          x_ff <= enc_in[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
          y_ff <= enc_in[(SIMON_DATA_W/2)-1:0];
          roundCount <= 0;
`ifdef SIMON_DEBUG
          $display("%t ++++++ Simon ENC in  ++++++", $time);
          $display("%t %m simon_enc.x_ff=0x%x", $time, enc_in[127:64]);
          $display("%t %m simon_enc.y_ff=0x%x", $time, enc_in[63:0]);
          $display("%t %m simon_enc.roundCount=%d", $time, 0);
          $display("%t %m simon_dec.local_enc_valid_o =%d", $time, local_enc_valid_o );
          $display("%t ------ Simon ENC in  ------", $time);
`endif /* SIMON_DEBUG */
        end
        else begin
          // We're available but no one needs us right now -- should be able to just maintain state
          busy <= `false;
          x_ff <= 0;
          y_ff <= 0;
          roundCount <= 0;
        end
      end
    end
  end
endmodule

module simon_cl_decryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS
) (
   input  logic [SIMON_DATA_W-1:0] dec_in,
   input  logic [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1],
   output logic [SIMON_DATA_W-1:0] dec_out
);
  typedef logic [$clog2(SIMON_ROUNDS+1)-1:0] xy_idx_t;
  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS]  /*verilator split_var*/;

  genvar i;
  generate

    assign x_words[0] = dec_in[(SIMON_DATA_W/2)-1:0];
    assign y_words[0] = dec_in[SIMON_DATA_W-1:(SIMON_DATA_W/2)];

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
      assign x_words[i + 1] = temp[i] ^ keytab[(SIMON_ROUNDS - i - 1)];
    end
  endgenerate

  assign dec_out ={y_words[xy_idx_t'(SIMON_ROUNDS)], x_words[xy_idx_t'(SIMON_ROUNDS)]};

endmodule

module simon_core_decryptor #(
   parameter int unsigned SIMON_DATA_W,
   parameter bit [6:0] SIMON_ROUNDS,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE
) (
   input  logic  clk,
   input  logic  rst,
   input  logic  data_valid_i,
   input  logic  [SIMON_DATA_W-1:0] dec_in,
   input  logic  [(SIMON_DATA_W/2)-1:0] keytab[0:SIMON_ROUNDS - 1],
   output logic  ready_o,
   output logic  [SIMON_DATA_W-1:0] dec_out,
   output logic  dec_valid_o
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  logic [(SIMON_DATA_W/2)-1:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  logic [(SIMON_DATA_W/2)-1:0] y_ff;
  logic [(SIMON_DATA_W/2)-1:0] x_ff;
  logic busy;
  logic [(SIMON_DATA_W/2)-1:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;

  logic [6:0] roundCount;
  logic local_dec_valid_o;

  assign ready_o = !busy;
  assign dec_valid_o = local_dec_valid_o;

`ifdef notdef
  initial begin
    $monitor("%t %m rst=%d", $time, rst);
    $monitor("%t %m local_dec_valid_o=%d", $time, local_dec_valid_o);
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    $strobe("%t %m rst=%d", $time, rst);
    $strobe("%t %m local_dec_valid_o=%d", $time, local_dec_valid_o);
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    //$display("dec input: %h", dec_in);
    //$write("x_words[%d]: %h, ", 0, x_words[0]);
    //$write("y_words[%d]: %h, ", 0, y_words[0]);

    //$display("rst: %h", rst);
    //$display("data_valid_i: %h", data_valid_i);
    //$display("busy: %h", busy);
    $monitor("x_ff: %h", x_ff);
    $monitor("y_ff: %h", y_ff);
    //$display("dec output: %h", dec_out);
    //$display("output valid: %b", local_dec_valid_o);
    //$display("Done: %b", done);
    $display("roundCount: %d", roundCount);
    //$display("cycleCount: %d", cycleCount);
  end
`endif /* notdef */
  
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
      assign temp[i] = (( {x_words[i][(SIMON_DATA_W/2)-2:0], x_words[i][(SIMON_DATA_W/2)-1]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][(SIMON_DATA_W/2)-9:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-8]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][(SIMON_DATA_W/2)-3:0], x_words[i][(SIMON_DATA_W/2)-1:(SIMON_DATA_W/2)-2]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
                       );
      
      // Calculate the cycle count
      //assign cycleCount = (i == `SIMON_ROUNDS_PER_CYCLE - 1) ? (cycleCount + 1) : cycleCount;  
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      // TMA: assign x_words[i + 1] = temp[i] ^ keytab[`SIMON_ROUNDS - (roundCount + i) - 1];
      assign x_words[i + 1] = temp[i] ^ keytab[(SIMON_ROUNDS - i - 1) - roundCount];
       
`ifdef notdef
      always_comb begin
        $write("x_words[%d]: %h, ", i + 1, x_words[i + 1]);
        $write("y_words[%d]: %h, ", i + 1, y_words[i + 1]);
        $display("temp[%d]: %h", i + 1, temp[i + 1]);
      end
`endif /* notdef */
    end
  endgenerate

  always_ff @(posedge clk) begin
          
    if (rst) begin
      busy <= `false;
      local_dec_valid_o <= `false;
      roundCount <= 0;
      y_ff <= 0;
      x_ff <= 0;
      dec_out <= 0;
    end
    else begin
      if (busy) begin
        if (local_dec_valid_o) begin
          // Output has been latched and we can reset everything
          busy <= `false;
          local_dec_valid_o <= `false;
          roundCount <= 0;
          y_ff <= 0;
          x_ff <= 0;
        end
        else begin
          /* verilator lint_off UNSIGNED */
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin /* verilator lint_on UNSIGNED */
            // In body, still have work to do -- perform an intermediate latch now
            busy <= busy;
            roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE;
            y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
            x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
          end
          else begin
            if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
              // Finishing up the tail; latch from tail and set output to valid
              busy <= busy;
              local_dec_valid_o <= `true;
              roundCount <= roundCount + (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE);
              y_ff <= y_ff; // Don't care
              x_ff <= x_ff; // Don't care
              dec_out <= {y_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], x_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]};
`ifdef SIMON_DEBUG
              $display("%t ++++++ Simon DEC out (tail) ++++++", $time);
              $display("%t %m simon_dec.dec_out=0x%x", $time,
                      {y_words[(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], x_words[(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]});
              $display("%t %m simon_dec.roundCount=%d", $time, roundCount + (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE));
              $display("%t ------ Simon DEC out (tail) ------", $time);
`endif /* SIMON_DEBUG */
            end
            else begin
              // Finishing up with no tail; latch from body and set output to valid
              busy <= busy;
              local_dec_valid_o <= `true;
              roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE; 
              y_ff <= y_ff; // Don't care
              x_ff <= x_ff; // Don't care
              dec_out <= {y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)], x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)]};
              //done <= 2;
`ifdef SIMON_DEBUG
              $display("%t ++++++ Simon DEC out (no tail) ++++++", $time);
              $display("%t %m simon_dec.dec_out=0x%x", $time, {y_words[SIMON_ROUNDS_PER_CYCLE], x_words[SIMON_ROUNDS_PER_CYCLE]});
              $display("%t %m simon_dec.roundCount=%d", $time, roundCount + SIMON_ROUNDS_PER_CYCLE);
              $display("%t ------ Simon DEC out (no tail) ------", $time);
`endif /* SIMON_DEBUG */
            end
          end
        end
      end
      else begin
        if (data_valid_i) begin
          // We're available and a request is being made -- latch input
          busy <= `true;
          y_ff <= dec_in[SIMON_DATA_W-1:(SIMON_DATA_W/2)];
          x_ff <= dec_in[(SIMON_DATA_W/2)-1:0];
          roundCount <= 0;
`ifdef SIMON_DEBUG
          $display("%t ++++++ Simon DEC in  ++++++", $time);
          $display("%t %m simon_dec.y_ff=0x%x", $time, dec_in[127:64]);
          $display("%t %m simon_dec.x_ff=0x%x", $time, dec_in[63:0]);
          $display("%t %m simon_dec.roundCount=%d", $time, 0);
          $display("%t %m simon_dec.local_dec_valid_o=%d", $time, local_dec_valid_o);
          $display("%t ------ Simon DEC in  ------", $time);
`endif /* SIMON_DEBUG */
        end
        else begin
          // We're available but no one needs us right now -- should be able to just maintain state
          busy <= `false;
          x_ff <= 0;
          y_ff <= 0;
          roundCount <= 0;
        end
      end
    end
  end
endmodule

