//------------------ SIMON DEFINES -------------------------------
`define true  1'b1
`define false 1'b0

typedef int unsigned uint32_t;
typedef enum logic [1:0] {
  SIMON_IDLE      = 2'b00,
  SIMON_KEYEXPAND = 2'b01,
  SIMON_ENCRYPT   = 2'b10,
  SIMON_DECRYPT   = 2'b11
} simon_op_e /*verilator public*/;

module simon_128_128_core #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd68,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
    input  wire         clk, rst,
    // input ports
    input  simon_op_e   op_i,
    input  logic        key_valid_i,
    input  wire [7:0]   key_i [0:15],
    input  logic        data_valid_i,
    input  wire [127:0] data_i,

    // output ports
    output logic        ready_o,
    output logic        data_valid_o,
    output wire [127:0] data_o
);
  longint unsigned /* logic [63:0] */ key_table[0:SIMON_ROUNDS - 1];
  logic keyexpand_valid_o, encrypt_valid_o, decrypt_valid_o;
  logic keyexpand_ready_o, encrypt_ready_o, decrypt_ready_o;
  logic [127:0] enc_data_o;
  logic [127:0] dec_data_o;

  simon_128_128_keyexpand #() keyexpand_inst (
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

  simon_128_128_encryptor #() encryptor_inst (
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

  simon_128_128_decryptor #() decryptor_inst (
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

module simon_128_128_keyexpand #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd68,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire        clk, rst, enable,
   input  wire [7:0]  key_in [0:15],
   input  wire        output_acknowledged,
   output logic       ready_o,
   output longint unsigned /* logic [63:0] */ key_expanded[0:SIMON_ROUNDS - 1],
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

  longint unsigned /* logic [63:0] */ tmp0;
  longint unsigned /* logic [63:0] */ tmp1;
  longint unsigned /* logic [63:0] */ tmp2;
  logic           busy;
  logic [6:0]     current_iter, current_iter_minus1, current_iter_minus2, next_iter;
  logic           local_output_valid;
  longint unsigned /* logic [63:0] */    key_words[0:SIMON_ROUNDS - 1];

  assign ready_o = !busy;

  const logic [65:0] z = 66'b010111_0011011010_0111111000_1000010100_0110010010_1100000011_1011110101;
  assign output_valid = local_output_valid;

  // always_comb begin
    assign tmp0 = key_words[current_iter_minus1];
    assign tmp1 = {tmp0[2:0], tmp0[63:3]};
    assign tmp2 =  tmp1 ^ {tmp1[0], tmp1[63:1]};
    assign next_iter = current_iter + 1;
  // end

  always_comb begin
    //$strobe("%t %m current_iter=%d", $time, current_iter);
    //$strobe("%t %m next_iter=%d", $time, next_iter);
    /*
    $strobe("%t %m local_output_valid=%d", $time, local_output_valid);
    $strobe("%t %m key_out_valid=%d", $time, output_valid);
    
    $strobe("%t %m key_out[0]=%h", $time, key_expanded[0]);
    $strobe("%t %m key_out[1]=%h", $time, key_expanded[1]);
    $strobe("%t %m key_out[2]=%h", $time, key_expanded[2]);
    $strobe("%t %m key_out[66]=%h", $time, key_expanded[66]);
    $strobe("%t %m key_out[67]=%h", $time, key_expanded[67]);
    //$strobe("%t %m key_words[0]=%h", $time, key_words[0]);
    
    $strobe("%t %m busy=%d", $time, busy);
    $strobe("%t %m enable=%d", $time, enable);
    $strobe("%t %m key_in[0]=%h", $time, key_in[0]);
    */
  end

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
      current_iter <= 2;
      current_iter_minus1 <= 1;
      current_iter_minus2 <= 0;
      key_words <= /* '{default:'0}; */ {64'ha6d2ae2816157e2b, 64'h3c4fcf098815f7ab, 64'h8d6054c640696059, 64'h6aca3f22dbe1b259, 64'hc96a4f2fc954b2ca, 64'h608e2dca21a190d0,
            64'h3c8c97b5d0856620, 64'h9b2889b83946958b, 64'h9a4f1e6abc62234, 64'ha579a765797dcc13, 64'hb8a3a083ac81b88b, 64'h96181682c9da1f77,
            64'hccfedcc426d8a56f, 64'h6cb7df29f0937e71, 64'h85ca52c783c02ba, 64'h72c67e2147e8c1f1, 64'hced7f2f5bb406967, 64'h80e00af54cb35b7,
            64'ha0a92d155b6a4376, 64'h49ee482355ef2612, 64'h32f5ff6cfb76aa28, 64'h336057c7fac96608, 64'h48500f17847cef75, 64'h3110a92b8dfecaec,
            64'hf29cef5fb2e3257a, 64'h3f9505ca7f7363e8, 64'h8968e045a50580c4, 64'h19d168396e7c7400, 64'h7430243ee1d236f8, 64'h6feb9102a3a4ee4d,
            64'hf0cc10f160631a28, 64'h1012dec66514356, 64'haf03d86dd533d98b, 64'h31ee9498fe5bfa03, 64'h5df1c48bae2e696, 64'h6ef7792a9d567744,
            64'h31117b00bf62b0f7, 64'h43bbe057eb3f5a9, 64'h7e2a48dfb8a00ee4, 64'h33e3ac6c8dd20b67, 64'h1497f86b1e3890c2, 64'hafc7d318a0096f8e,
            64'hd46c80c67fc6d437, 64'hd7f374f3f7f227b7, 64'hac1226e8c1b84d46, 64'h974fedbf9c215536, 64'he870da7b34018d4e, 64'h5b3904a8b61e83b6,
            64'hb95b955b565c4afe, 64'h987830a9964f31bb, 64'h8c2cefbb020ea02f, 64'h6ec09c5ab9d1f040, 64'h78e70a0a01567edf, 64'h89adf244a611a78b,
            64'h4eb79499200aafaa, 64'h9b6f8661efefa779, 64'h1b9363ccfcf65ecf, 64'h765b23db4041f6b0, 64'hedc24a75df05808f, 64'h8ac0b1cd59aee154,
            64'hcbc9a8af5e554d4c, 64'h20fae1adb87ee3d5, 64'hc226a57fcd2280f6, 64'h6b63a0aa42f76439, 64'h8603149fdeace5cf, 64'h9c3c0c8fbb37c920,
            64'h63b8aa392d869f84, 64'ha98f6c94f3a08cd4}; 
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
            current_iter <= 2;
            current_iter_minus1 <= 1;
            current_iter_minus2 <= 0;
        end
        // Not done yet
        else begin 
          // On last round
          if (current_iter == SIMON_ROUNDS) begin
            local_output_valid <= `true;
            key_expanded <= key_words;
          end
          // Not on last round yet
          else begin
            key_words[current_iter] <= 64'hFFFFFFFFFFFFFFFC ^ key_words[current_iter_minus2] ^ tmp2 ^ {63'h0, z[current_iter_minus2]};
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
          current_iter <= 2;
          current_iter_minus1 <= 1;
          current_iter_minus2 <= 0;
          busy <= `true;
          input_acknowledged <= `true;
          // Set first two elements of key table to original key
          // Compiler wouldn't let me do this a nicer way
          //key_words[0:1] <= {key_in[0:7], key_in[8:15]};
          key_words[0] <= {key_in[7], key_in[6], key_in[5], key_in[4], key_in[3], key_in[2], key_in[1], key_in[0]};
          key_words[1] <= {key_in[15], key_in[14], key_in[13], key_in[12], key_in[11], key_in[10], key_in[9], key_in[8]};
`ifdef notdef
          foreach(key_in[q]) $display("%t %m key_in[%d]=0x%x", $time, q, key_in[q]);
`endif /* notdef */
        end
        // Idle and no incoming request
        else begin
          current_iter <= 2;
          current_iter_minus1 <= 1;
          current_iter_minus2 <= 0;
          busy <= `false;
          input_acknowledged <= `false;
        end
      end
    end
  end  
endmodule

module simon_128_128_encryptor #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd68,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire          clk, rst, enable,
   input  wire  [127:0] enc_in,
   input  wire          output_acknowledged,
   input longint unsigned /* logic [63:0] */ key_expanded[0:SIMON_ROUNDS - 1],
   output logic         ready_o,
   output logic [127:0] enc_out,
   output logic         input_acknowledged,
   output logic         output_valid
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE):0] xy_idx_t;

  wire [63:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] x_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  wire [63:0] y_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  logic [63:0] y_ff;
  logic [63:0] x_ff;
  logic busy;
  wire [63:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] temp_tail[0:SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE];

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

      assign temp[i] = (( {x_words[i][62:0], x_words[i][63]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][55:0], x_words[i][63:56]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][61:0], x_words[i][63:62]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
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
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin
              
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
          x_ff <= enc_in[127:64];
          y_ff <= enc_in[63:0];
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

module simon_128_128_decryptor #(
   parameter bit [6:0] SIMON_ROUNDS = 7'd68,
   parameter bit [6:0] SIMON_ROUNDS_PER_CYCLE = 7'd4
) (
   input  wire   clk, rst, enable,
   input  wire   [127:0] dec_in,
   input  wire   output_acknowledged,
   input longint unsigned /* logic [63:0] */ key_expanded[0:SIMON_ROUNDS - 1],
   output logic  ready_o,
   output logic  [127:0] dec_out,
   output logic  input_acknowledged,
   output wire   output_valid
);
  typedef logic [$clog2(SIMON_ROUNDS_PER_CYCLE):0] xy_idx_t;

  wire [63:0] y_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] x_words[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] x_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  wire [63:0] y_tail_words[0:(SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE)];
  logic [63:0] y_ff;
  logic [63:0] x_ff;
  logic busy;
  wire [63:0] temp[0:SIMON_ROUNDS_PER_CYCLE]  /*verilator split_var*/;
  wire [63:0] temp_tail[0:SIMON_ROUNDS_PER_CYCLE];

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
      assign temp[i] = (( {x_words[i][62:0], x_words[i][63]} /* ((x_words[i] << 1) | (x_words[i] >> (`WORD_SIZE - 1))) */
                          & {x_words[i][55:0], x_words[i][63:56]} /* ((x_words[i] << 8) | (x_words[i] >> (`WORD_SIZE - 8))) */
                        )
                        ^ y_words[i]
                        ^ {x_words[i][61:0], x_words[i][63:62]} /* ((x_words[i] << 2) | (x_words[i] >> (`WORD_SIZE - 2))) */
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
          if ((((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) == 0) && roundCount < SIMON_ROUNDS - SIMON_ROUNDS_PER_CYCLE) || (((SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE) != 0) && roundCount < SIMON_ROUNDS - (SIMON_ROUNDS % SIMON_ROUNDS_PER_CYCLE))) begin
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
          y_ff <= dec_in[127:64];
          x_ff <= dec_in[63:0];
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


