# simon-cipher

To build everything and run tests:
```
make clean build test
```

To run an individual test:
```
simon-test
obj_simon_64_32_core/Vsimon_core
obj_simon_128_64_core/Vsimon_core
obj_simon_128_128_core/Vsimon_core
```

# SIMON Cipher Implementation (Software + Hardware)

This repository contains a dual **software** (C++ reference model) and **hardware** (SystemVerilog RTL) implementation of the [SIMON cipher](https://en.wikipedia.org/wiki/Simon_(cipher)), a family of lightweight block ciphers designed by the NSA. SIMON is optimized for constrained environments such as IoT devices, embedded systems, and low-power secure hardware.

The project demonstrates:
- A **C++ software implementation** that serves as the golden model.
- A **SystemVerilog hardware implementation** that is synthesizable for FPGA/ASIC targets.
- A **unified verification flow**, where hardware outputs are validated against the software reference.
- Full **parameterization** of algorithm properties (block size, key size, number of rounds) and microarchitectural choices (rounds per cycle).

---

## 📂 Repository Overview

```
.
├── .gitignore
├── Makefile              # Build automation for both C++ and Verilator simulations
├── README.md             # Project documentation (this file)
├── simon.cpp             # Core C++ SIMON cipher implementation
├── simon.h               # Cipher API header
├── simon_internal.h      # Internal constants, macros, and configuration
├── simon-test.cpp        # Test program for validating software implementation
├── simon_core.sv         # SystemVerilog RTL implementation of SIMON core
└── tb_simon_core.cpp     # C++ testbench for Verilator hardware simulation
```

---

## 🔹 Software Implementation (C++)

The software model implements the SIMON cipher algorithm in portable C++. It is designed for:
- **Correctness**: trusted golden reference.
- **Ease of testing**: run quickly on any host machine.
- **Parameter exploration**: different SIMON variants can be configured.

### Key Components
- **Key Schedule**: Expands master key into round keys.
- **Round Function**:  
  The SIMON round uses only lightweight bitwise operations:
  ```c++
  tmp = (ROL(x,1) & ROL(x,8)) ^ ROL(x,2) ^ y ^ round_key[i];
  y = x;
  x = tmp;
  ```
- **Encrypt/Decrypt**: Forward and backward application of the round function.
- **Test Harness**: `simon-test.cpp` runs known vectors and prints pass/fail.

---

## 🔹 Hardware Implementation (SystemVerilog)

The RTL design provides a synthesizable SIMON core.

### Features
- **Datapath**: Implements the Feistel structure with AND, XOR, and rotations.
- **FSM**: Controls stepping through rounds.
- **Inputs/Outputs**: Accepts plaintext/key, outputs ciphertext.
- **Testbench (`tb_simon_core.cpp`)**:  
  - Compiled with [Verilator](https://www.veripool.org/verilator/).
  - Provides test vectors to the RTL.
  - Compares RTL outputs against the software golden model.

---

## 🔹 Software + Hardware Integration

- The **C++ implementation** acts as the “golden model”.
- The **SystemVerilog implementation** is simulated using Verilator.
- The **testbench** feeds identical inputs to both and ensures outputs match.
- This unified flow guarantees the RTL design is functionally correct.

---

## 🔹 Build and Test Instructions

### Software (C++)
```bash
make
./simon-test
```
- Compiles the C++ cipher implementation.
- Runs test vectors to confirm correctness.

### Hardware (SystemVerilog via Verilator)
```bash
make simon_core_tb
./simon_core_tb
```
- Builds the Verilated RTL model of `simon_core.sv`.
- Runs `tb_simon_core.cpp` testbench.
- Compares hardware outputs with the software reference.

Expected output: *all vectors pass*.

---

## 🔹 Software Parameterization

The C++ code can be configured for different SIMON variants:
- **Block size**: {32, 48, 64, 96, 128} bits.
- **Key size**: {64, 72, 96, 128, 144, 192, 256} bits.
- **Rounds**: Variant-dependent (e.g., 32, 36, 44, 52, 68, 72).
- **Rotation constants**: Each variant uses specific shifts (e.g., 1, 8, 2).

These constants are defined in `simon_internal.h`.

### Example
```c++
#define SIMON_BLOCK_SIZE 64
#define SIMON_KEY_SIZE   128
#define SIMON_ROUNDS     44
```

---

## 🔹 Hardware Parameterization

The RTL module is written with generics for flexibility:

```systemverilog
module simon_core #(
    parameter BLOCK_SIZE       = 64,   // block size in bits
    parameter KEY_SIZE         = 128,  // key size in bits
    parameter ROUNDS           = 44,   // number of rounds
    parameter ROUNDS_PER_CYCLE = 1     // rounds computed per cycle
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [BLOCK_SIZE-1:0] plaintext,
    input  logic [KEY_SIZE-1:0]   key,
    output logic [BLOCK_SIZE-1:0] ciphertext,
    output logic done
);
```

### Parameters
- **BLOCK_SIZE**: Data block width.
- **KEY_SIZE**: Key width.
- **ROUNDS**: Total rounds.
- **ROUNDS_PER_CYCLE**: Controls microarchitecture.

---

## 🔹 Rounds-per-Cycle Design Tradeoffs

- **Iterative (1 round/cycle)**  
  - Area-efficient, slow.  
  - Latency = `ROUNDS` cycles.  

- **Partially Unrolled (N rounds/cycle)**  
  - Multiple rounds computed per cycle.  
  - Latency = `ROUNDS / N` cycles.  
  - Balance between throughput and area.  

- **Fully Unrolled (all rounds/cycle)**  
  - Entire cipher computed in 1 cycle.  
  - Max throughput, very high area and critical path.  

---

## 🔹 Example Test Vectors

For SIMON64/128 (block = 64 bits, key = 128 bits, 44 rounds):

- **Key**: `1b1a1918131211100b0a090803020100`
- **Plaintext**: `656b696c20646e75`
- **Expected Ciphertext**: `44c8fc20b9dfa07a`

These can be used to validate both software and hardware implementations.

---

## ✅ Summary

This repository provides:
- A **C++ golden model** for the SIMON cipher.
- A **SystemVerilog RTL core** for FPGA/ASIC targets.
- **Unified verification** using Verilator and C++ testbenches.
- Full **parameterization** to explore algorithmic and architectural tradeoffs.

It serves as:
- A teaching resource for lightweight cryptography.
- A reference design for FPGA projects.
- A starting point for secure hardware integration in SoCs.

