# SIMON Cipher: C/C++ Reference Model and SystemVerilog RTL

This repository provides an open-source implementation of the [SIMON block cipher](https://en.wikipedia.org/wiki/Simon_(cipher)) for software and hardware development. It includes:

- A C-style C++ reference implementation derived from the implementation in the original SIMON specification.
- A synthesizable, parameterized SystemVerilog implementation for FPGA and ASIC designs.
- Published encryption and decryption test vectors.
- A C++/Verilator RTL test harness and randomized fuzzer that compare the hardware against the software golden model.

The complete flow uses [GCC](https://gcc.gnu.org/) and [Verilator](https://www.veripool.org/verilator/), so the implementation and its verification environment can be built entirely with open-source tools.

## Why SIMON?

SIMON is a Feistel-based family of lightweight block ciphers designed for efficient hardware implementation. Its round function is composed only of fixed rotations, an AND, and XORs. In simplified form, each round computes:

```text
new_x = y ^ (ROL(x, 1) & ROL(x, 8)) ^ ROL(x, 2) ^ round_key
new_y = x
```

This simple structure makes SIMON highly tunable. A hardware designer can trade area, latency, throughput, and critical-path length by changing the number of rounds evaluated per cycle. That flexibility is useful both for complete cipher engines and for reduced-round microarchitectural primitives—for example, encrypting a cache index in a randomized cache.

With appropriate unrolling, flattening, and gate-level optimization, a SIMON round can have a delay of roughly four fan-out-of-four (FO4) inverter delays. This is an implementation target rather than a guarantee: actual timing depends on the cell library, synthesis constraints, physical design, and selected architecture.

## Repository Contents

| Path | Description |
| --- | --- |
| `simon.cpp`, `simon.h`, `simon_internal.h` | Software reference model, public API, key schedule, and variant-specific definitions. |
| `simon-test.cpp` | Software tests using published SIMON encryption and decryption vectors. |
| `simon_core.sv` | Parameterized SystemVerilog key expansion, encryption, and decryption logic. |
| `tb_simon_core.cpp` | Verilator test harness and randomized differential fuzzer. |
| `Makefile` | GCC and Verilator build, test, and long-test targets. |

## Supported Configurations

The checked-in build verifies these configurations:

| Key width | Block width | Rounds | Rounds per cycle |
| ---: | ---: | ---: | ---: |
| 64 bits | 32 bits | 32 | 12 |
| 128 bits | 64 bits | 44 | 12 |
| 128 bits | 128 bits | 68 | 12 |

The RTL exposes the following parameters:

- `SIMON_KEY_W`: key width; the current implementation supports 64- and 128-bit keys.
- `SIMON_DATA_W`: block width; the current implementation supports 32-, 64-, and 128-bit blocks.
- `SIMON_ROUNDS`: number of cipher rounds.
- `SIMON_ROUNDS_PER_CYCLE`: number of rounds implemented in the per-cycle combinational datapath.

Changing `SIMON_ROUNDS_PER_CYCLE` changes the hardware tradeoff:

- **Fewer rounds per cycle** generally reduce combinational depth and area while increasing operation latency.
- **More rounds per cycle** generally increase combinational depth and area while reducing operation latency.
- The RTL also contains fully combinational encryption and decryption paths for evaluating completely unrolled operation.

Because the key size, block size, round count, and rounds per cycle are parameters, most projects can explore different implementations without editing the round logic itself. New configurations should always be validated against the software model and reviewed for compatibility with the SIMON variant being implemented.

## Verification Strategy

Verification has two layers:

1. `simon-test` checks software encryption and decryption against published SIMON vectors.
2. Each Verilated RTL executable:
   - checks fixed encryption and decryption vectors;
   - generates random keys and data;
   - compares iterative RTL encryption and decryption with the software golden model;
   - compares fully combinational RTL encryption and decryption with the software model; and
   - performs end-to-end encrypt/decrypt trials.

The default `make test` target runs two million randomized trials for each checked-in hardware configuration. `make longtest` increases that to twenty million trials per configuration. This differential-fuzzing setup is intended to support thorough functional verification across implementation configurations and PVT sign-off flows; users remain responsible for project-specific coverage, formal analysis, timing closure, and physical validation.

## Build and Test

### Prerequisites

Install:

- GNU Make
- GCC/G++
- Verilator

### Build everything and run the default RTL fuzz tests

```bash
make clean build test
```

### Run the software vector tests

```bash
./simon-test
```

### Run an individual RTL configuration

```bash
./obj_simon_64_32_core/Vsimon_core --maxtrials 2000000
./obj_simon_128_64_core/Vsimon_core --maxtrials 2000000
./obj_simon_128_128_core/Vsimon_core --maxtrials 2000000
```

Use `--maxtrials N` to select the number of randomized trials for an RTL executable.

### Run the extended fuzz suite

```bash
make longtest
```

## Example Published Vector

For SIMON64/128 (64-bit block, 128-bit key, 44 rounds):

- **Key:** `1b1a1918131211100b0a090803020100`
- **Plaintext:** `656b696c20646e75`
- **Ciphertext:** `44c8fc20b9dfa07a`

The software and RTL tests include this vector for both encryption and decryption validation.

## Resources

- Repository: <https://github.com/toddmaustin/simon-cipher>
- Background: [SIMON on Wikipedia](https://en.wikipedia.org/wiki/Simon_(cipher))

Issues, test results, implementation feedback, and contributions are welcome.
