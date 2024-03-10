//------------------ SIMON DEFINES -------------------------------
`define true  1'b1
`define false 1'b0

typedef enum logic [1:0] {
  SIMON_IDLE      = 2'b00,
  SIMON_KEYEXPAND = 2'b01,
  SIMON_ENCRYPT   = 2'b10,
  SIMON_DECRYPT   = 2'b11
} simon_op_e /*verilator public*/;

module simon_128_64_core #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd44,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd12
) (
    input  wire         clk, rst,
    // input ports
    input  simon_op_e   op_i,
    input  logic        key_valid_i,
    input  wire [7:0]   key_i [0:15],
    input  logic        data_valid_i,
    input  wire [63:0] data_i,

    // output ports
    output logic        ready_o,
    output logic        data_valid_o,
    output wire [63:0] data_o
);
  logic [31:0] key_table[0:SIMON_ROUNDS - 1];
  logic keyexpand_valid_o, encrypt_valid_o, decrypt_valid_o;
  logic keyexpand_ready_o, encrypt_ready_o, decrypt_ready_o;
  logic [63:0] enc_data_o;
  logic [63:0] dec_data_o;

  simon_128_64_keyexpand #(
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
) keyexpand_inst (
   .clk               (clk),
   .rst               (rst),
   .enable            (key_valid_i),
   .key_in            (key_i),
   .key_expanded      (key_table),
   .output_valid      (keyexpand_valid_o),
   .input_acknowledged (),
   .output_acknowledged (`true),
   .ready_o           (keyexpand_ready_o)
  );

  simon_128_64_encryptor #(
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
) encryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .enable            (data_valid_i),
   .enc_in            (data_i),
   .enc_out           (enc_data_o),
   .key_expanded      (key_table),
   .output_valid      (encrypt_valid_o),
   .input_acknowledged (),
   .output_acknowledged (`true),
   .ready_o           (encrypt_ready_o)
  );

  simon_128_64_decryptor #(
  .SIMON_ROUNDS           (SIMON_ROUNDS),
  .SIMON_ROUNDS_PER_CYCLE (SIMON_ROUNDS_PER_CYCLE)
) decryptor_inst (
   .clk               (clk),
   .rst               (rst),
   .enable            (data_valid_i),
   .dec_in            (data_i),
   .dec_out           (dec_data_o),
   .key_expanded      (key_table),
   .output_valid      (decrypt_valid_o),
   .input_acknowledged (),
   .output_acknowledged (`true),
   .ready_o           (decrypt_ready_o)
  );

  assign data_valid_o = keyexpand_valid_o | encrypt_valid_o | decrypt_valid_o;
  assign ready_o = keyexpand_ready_o & encrypt_ready_o & decrypt_ready_o;

  always_comb begin
    unique case (op_i)
      SIMON_IDLE,
      SIMON_KEYEXPAND:    data_o = 0;
      SIMON_ENCRYPT:      data_o = enc_data_o;
      SIMON_DECRYPT:      data_o = dec_data_o;
    endcase
  end

endmodule;

module simon_128_64_keyexpand #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd44,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire        clk, rst, enable,
   input  wire [7:0]  key_in [0:15],
   input  wire        output_acknowledged,
   output logic       ready_o,
   output logic [31:0] key_expanded[0:SIMON_ROUNDS - 1],
   output logic       input_acknowledged,
   output logic       output_valid
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

  logic [31:0] tmp0;
  logic [31:0] tmp1;
  logic [31:0] tmp1a;
  logic [31:0] tmp2;
  logic           busy;
  logic [6:0]     current_iter, current_iter_minus1, current_iter_minus2, next_iter;
  logic           local_output_valid;
  logic [31:0] key_words[0:SIMON_ROUNDS - 1];

  assign ready_o = !busy;

  // const logic [65:0] z = 66'b010111_0011011010_0111111000_1000010100_0110010010_1100000011_1011110101;
  const logic [65:0] z = 66'h7c2c_e512_07a6_35db;
  assign output_valid = local_output_valid;

  assign tmp0 = key_words[current_iter_minus1];
  assign tmp1 = {tmp0[2:0], tmp0[31:3]};
  assign tmp1a = tmp1 ^ key_words[current_iter-3];
  assign tmp2 =  tmp1a ^ {tmp1a[0], tmp1a[31:1]};
  assign next_iter = current_iter + 1;

  always_ff @(posedge clk) begin
`ifdef notdef
    if (busy) begin
      $display("%t %m key_expander.input_acknowledged=%d", $time, input_acknowledged);
      $display("%t %m key_expander.local_output_valid=%d", $time, local_output_valid);
      $display("%t %m key_expander.current_iter=%d", $time, current_iter);
      $display("%t %m key_expander.current_iter_minus1=%d", $time, current_iter_minus1);
      $display("%t %m key_expander.current_iter_minus2=%d", $time, current_iter_minus2);
    end
`endif /* notdef */
    if (rst) begin
      busy <= `false;
      input_acknowledged <= `false;
      local_output_valid <= `false;
      current_iter <= 4;
      current_iter_minus1 <= 3;
      current_iter_minus2 <= 2;
      key_words <= '{default:'0};
      key_expanded <= '{default:'0};
    end
    else begin
      // In the middle of doing a key expansion
      if (busy) begin
        if (local_output_valid) begin
            // Output has been latched and we can reset everything
            busy <= `false;
            input_acknowledged <= `false;
            local_output_valid <= `false;
            current_iter <= 4;
            current_iter_minus1 <= 3;
            current_iter_minus2 <= 2;
        end
        // Not done yet
        else begin 
          // On last round
          if (current_iter == SIMON_ROUNDS) begin
            local_output_valid <= `true;
            key_expanded <= key_words;
`ifdef notdef
            foreach(key_words[q]) $display("%t %m key_words[%d]=0x%x", $time, q, key_words[q]);
`endif /* notdef */
          end
          // Not on last round yet
          else begin
            key_words[current_iter] <= 32'hFFFFFFFC ^ key_words[current_iter-4] ^ tmp2 ^ {31'h0, z[current_iter-4]};
            current_iter <= next_iter;
            current_iter_minus1 <= next_iter - 1;
            current_iter_minus2 <= next_iter - 2;
          end
        end
      end
      // Idle
      else begin
        // Can handle incoming request
        if (enable) begin
          current_iter <= 4;
          current_iter_minus1 <= 3;
          current_iter_minus2 <= 2;
          busy <= `true;
          input_acknowledged <= `true;
          // Set first two elements of key table to original key
          // Compiler wouldn't let me do this a nicer way
          //key_words[0:1] <= {key_in[0:7], key_in[8:15]};
          // key_words[0] <= {key_in[7], key_in[6], key_in[5], key_in[4], key_in[3], key_in[2], key_in[1], key_in[0]};
          // key_words[1] <= {key_in[15], key_in[14], key_in[13], key_in[12], key_in[11], key_in[10], key_in[9], key_in[8]};
          key_words[0] <= {key_in[3], key_in[2], key_in[1], key_in[0]};
          key_words[1] <= {key_in[7], key_in[6], key_in[5], key_in[4]};
          key_words[2] <= {key_in[11], key_in[10], key_in[9], key_in[8]};
          key_words[3] <= {key_in[15], key_in[14], key_in[13], key_in[12]};
`ifdef notdef
          foreach(key_in[q]) $display("%t %m key_in[%d]=0x%x", $time, q, key_in[q]);
`endif /* notdef */
        end
        // Idle and no incoming request
        else begin
          current_iter <= 4;
          current_iter_minus1 <= 3;
          current_iter_minus2 <= 2;
          busy <= `false;
          input_acknowledged <= `false;
        end
      end
    end
  end  
endmodule

module simon_128_64_encryptor #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd44,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire          clk, rst, enable,
   input  wire  [63:0] enc_in,
   input  wire          output_acknowledged,
   input  logic [31:0] key_expanded[0:SIMON_ROUNDS - 1],
   output logic         ready_o,
   output logic [63:0] enc_out,
   output logic         input_acknowledged,
   output logic         output_valid
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  wire [31:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] x_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  wire [31:0] y_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  logic [31:0] y_ff;
  logic [31:0] x_ff;
  logic busy;
  wire [31:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] temp_tail[0:SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE];

  assign ready_o = !busy;

  logic [6:0] roundCount;
  logic done;
  logic local_output_valid;

  assign output_valid = local_output_valid;

`ifdef notdef
  always_comb begin
    $display("enc input: %h", enc_in);
    $write("x_words[%d]: %h, ", 0, x_words[0]);
    $write("y_words[%d]: %h, ", 0, y_words[0]);

    $display("rst: %h", rst);
    $display("enable: %h", enable);
    $display("busy: %h", busy);
    $display("x_ff: %h", x_ff);
    $display("y_ff: %h", y_ff);
    $display("enc output: %h", enc_out);
    $display("output valid: %b", local_output_valid);
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

      assign temp[i] = (( {x_words[i][30:0], x_words[i][31]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][23:0], x_words[i][31:24]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][29:0], x_words[i][31:30]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
                       );
      
      // Calculate the cycle count
      //assign cycleCount = (i == `SIMON_ROUNDS_PER_CYCLE - 1) ? (cycleCount + 1) : cycleCount;  
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      assign x_words[i + 1] = temp[i] ^ key_expanded[roundCount + i];
       
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
    $monitor("%t %m local_output_valid=%d", $time, local_output_valid);
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    $strobe("%t %m rst=%d", $time, rst);
    $strobe("%t %m local_output_valid=%d", $time, local_output_valid);
  end
`endif /* notdef */

  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= 0;
      input_acknowledged = 0;
      local_output_valid <= 0;
      roundCount <= 0;
      y_ff <= 0;
      x_ff <= 0;
      enc_out <= 0;
    end
    else begin
      //cycleCount <= cycleCount + 1;
      if (busy) begin
        if (local_output_valid) begin
          if (output_acknowledged) begin
            // Output has been latched and we can reset everything
            busy <= 0;
            input_acknowledged = 0;
            local_output_valid <= 0;
            roundCount <= 0;
            y_ff <= 0;
            x_ff <= 0;
          end
          else begin
            // We're done here but need to hold onto the output for it to be latched
            busy <= busy;
            input_acknowledged = input_acknowledged;
            roundCount <= roundCount;
            y_ff <= y_ff;
            x_ff <= x_ff;
            enc_out <= enc_out;
          end
        end
        else begin
          /* verilator lint_off UNSIGNED */
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin /* verilator lint_on UNSIGNED */
              
            // In body, still have work to do -- perform an intermediate latch now
            busy <= busy;
            input_acknowledged = input_acknowledged;
            roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE;
            y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
            x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
          end
          else begin
            if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
              // Finishing up the tail; latch from tail and set output to valid
              busy <= busy;
              input_acknowledged = input_acknowledged;
              local_output_valid <= 1;
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
              input_acknowledged = input_acknowledged;
              local_output_valid <= 1;
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
        if (enable) begin
          // We're available and a request is being made -- latch input
          busy <= 1;
          x_ff <= enc_in[63:32];
          y_ff <= enc_in[31:0];
          input_acknowledged = 1;
          roundCount <= 0;
`ifdef SIMON_DEBUG
          $display("%t ++++++ Simon ENC in  ++++++", $time);
          $display("%t %m simon_enc.x_ff=0x%x", $time, enc_in[127:64]);
          $display("%t %m simon_enc.y_ff=0x%x", $time, enc_in[63:0]);
          $display("%t %m simon_enc.roundCount=%d", $time, 0);
          $display("%t %m simon_dec.local_output_valid=%d", $time, local_output_valid);
          $display("%t ------ Simon ENC in  ------", $time);
`endif /* SIMON_DEBUG */
        end
        else begin
          // We're available but no one needs us right now -- should be able to just maintain state
          busy <= 0;
          x_ff <= 0;
          y_ff <= 0;
          input_acknowledged = 0;
          roundCount <= 0;
        end
      end
    end
  end
endmodule

module simon_128_64_decryptor #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd44,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire   clk, rst, enable,
   input  wire   [63:0] dec_in,
   input  wire   output_acknowledged,
   input  logic [31:0] key_expanded[0:SIMON_ROUNDS - 1],
   output logic  ready_o,
   output logic  [63:0] dec_out,
   output logic  input_acknowledged,
   output wire   output_valid
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE+1)-1:0] xy_idx_t;

  wire [31:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] x_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  wire [31:0] y_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  logic [31:0] y_ff;
  logic [31:0] x_ff;
  logic busy;
  wire [31:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [31:0] temp_tail[0:SIMON_ROUNDS_PER_CYCLE];

  logic [6:0] roundCount;
  logic done;
  logic local_output_valid;

  assign ready_o = !busy;
  assign output_valid = local_output_valid;

`ifdef notdef
  initial begin
    $monitor("%t %m rst=%d", $time, rst);
    $monitor("%t %m local_output_valid=%d", $time, local_output_valid);
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    $strobe("%t %m rst=%d", $time, rst);
    $strobe("%t %m local_output_valid=%d", $time, local_output_valid);
  end
`endif /* notdef */

`ifdef notdef
  always_comb begin
    //$display("dec input: %h", dec_in);
    //$write("x_words[%d]: %h, ", 0, x_words[0]);
    //$write("y_words[%d]: %h, ", 0, y_words[0]);

    //$display("rst: %h", rst);
    //$display("enable: %h", enable);
    //$display("busy: %h", busy);
    $monitor("x_ff: %h", x_ff);
    $monitor("y_ff: %h", y_ff);
    //$display("dec output: %h", dec_out);
    //$display("output valid: %b", local_output_valid);
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
      assign temp[i] = (( {x_words[i][30:0], x_words[i][31]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][23:0], x_words[i][31:24]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][29:0], x_words[i][31:30]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
                       );
      
      // Calculate the cycle count
      //assign cycleCount = (i == `SIMON_ROUNDS_PER_CYCLE - 1) ? (cycleCount + 1) : cycleCount;  
      // Feistel Cross        
      assign y_words[i + 1] = x_words[i];
      // XOR with round key  
      // TMA: assign x_words[i + 1] = temp[i] ^ key_expanded[`SIMON_ROUNDS - (roundCount + i) - 1];
      assign x_words[i + 1] = temp[i] ^ key_expanded[(SIMON_ROUNDS - i - 1) - roundCount];
       
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
      busy <= 0;
      input_acknowledged = 0;
      local_output_valid <= 0;
      roundCount <= 0;
      y_ff <= 0;
      x_ff <= 0;
      dec_out <= 0;
    end
    else begin
      if (busy) begin
        if (local_output_valid) begin
          if (output_acknowledged) begin
            // Output has been latched and we can reset everything
            busy <= 0;
            input_acknowledged = 0;
            local_output_valid <= 0;
            roundCount <= 0;
            y_ff <= 0;
            x_ff <= 0;
          end
          else begin
            // We're done here but need to hold onto the output for it to be latched
            busy <= busy;
            input_acknowledged = input_acknowledged;
            roundCount <= roundCount;
            y_ff <= y_ff;
            x_ff <= x_ff;
            dec_out <= dec_out;
          end
        end
        else begin
          /* verilator lint_off UNSIGNED */
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin /* verilator lint_on UNSIGNED */
            // In body, still have work to do -- perform an intermediate latch now
            busy <= busy;
            input_acknowledged = input_acknowledged;
            roundCount <= roundCount + SIMON_ROUNDS_PER_CYCLE;
            y_ff <= y_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
            x_ff <= x_words[xy_idx_t'(SIMON_ROUNDS_PER_CYCLE)];
          end
          else begin
            if ((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) begin
              // Finishing up the tail; latch from tail and set output to valid
              busy <= busy;
              input_acknowledged = input_acknowledged;
              local_output_valid <= 1;
              roundCount <= roundCount + (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE);
              y_ff <= y_ff; // Don't care
              x_ff <= x_ff; // Don't care
              dec_out <= {y_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)], x_words[xy_idx_t'(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)]};
              //done <= 1;
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
              input_acknowledged = input_acknowledged;
              local_output_valid <= 1;
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
        if (enable) begin
          // We're available and a request is being made -- latch input
          busy <= 1;
          y_ff <= dec_in[63:32];
          x_ff <= dec_in[31:0];
          input_acknowledged = 1;
          roundCount <= 0;
`ifdef SIMON_DEBUG
          $display("%t ++++++ Simon DEC in  ++++++", $time);
          $display("%t %m simon_dec.y_ff=0x%x", $time, dec_in[127:64]);
          $display("%t %m simon_dec.x_ff=0x%x", $time, dec_in[63:0]);
          $display("%t %m simon_dec.roundCount=%d", $time, 0);
          $display("%t %m simon_dec.local_output_valid=%d", $time, local_output_valid);
          $display("%t ------ Simon DEC in  ------", $time);
`endif /* SIMON_DEBUG */
        end
        else begin
          // We're available but no one needs us right now -- should be able to just maintain state
          busy <= 0;
          x_ff <= 0;
          y_ff <= 0;
          input_acknowledged = 0;
          roundCount <= 0;
        end
      end
    end
  end
endmodule


