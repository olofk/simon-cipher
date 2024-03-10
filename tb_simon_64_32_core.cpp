#include <stdlib.h>
#include <iostream>
#include <cstdlib>
#include <verilated.h>
#include "Vsimon_64_32_core.h"
#include "Vsimon_64_32_core___024unit.h"
#include "simon.h"

#define MAX_TRIALS    1000000000UL
#define MAX_SIM_TIME 400
#define VERIF_START_TIME 7

vluint64_t sim_time = 0;
vluint64_t posedge_cnt = 0;

#include <stdint.h>
typedef unsigned __int128 uint128_t;
#define HI64(X)        ((uint64_t)(((X) >> 64) & 0xffffffffffffffffULL))
#define LO64(X)        ((uint64_t)(((X))       & 0xffffffffffffffffULL))
#define GEN128(HI, LO) ((((uint128_t)(HI)) << 64) | ((uint128_t)(LO)))
#define TRUE  1
#define FALSE 0

uint64_t simon_64_32_key = 0x1918111009080100UL;
uint32_t simon_64_32_plaintext = 0x65656877;
uint32_t simon_64_32_ciphertext = 0xc69be9bb;

// generate a random integer
uint32_t
genrand32(void)
{
  // combine two calls to random(), since RAND_MAX is often less than 32 bits
  return ((uint32_t)random() << 16) ^ (uint32_t)random();
}

uint64_t
genrand64(void)
{
  return ((uint64_t)genrand32() << 32) ^ (uint64_t)genrand32();
}

uint128_t
genrand128(void)
{
  return (((uint128_t)genrand64()) << 64) | ((uint128_t)genrand64());
}

void
dut_reset (Vsimon_64_32_core *dut, vluint64_t &sim_time)
{
    dut->rst = FALSE;
    if(sim_time >= 3 && sim_time < 6){
        fprintf(stderr, "INFO: Reseting DUT @ cycle %lu...\n", sim_time/2);
        dut->rst = TRUE;
        dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_IDLE;
        dut->key_valid_i = FALSE;
        dut->data_valid_i = FALSE;
    }
}

void
check_out_valid(Vsimon_64_32_core *dut, vluint64_t &sim_time)
{
  static unsigned char in_valid = 0; //in valid from current cycle
  static unsigned char in_valid_d = 0; //delayed in_valid
  static unsigned char out_valid_exp = 0; //expected out_valid value

  if (sim_time >= VERIF_START_TIME)
  {
    if (dut->data_valid_o)
    {
      fprintf(stderr, "INFO: Request completed @ cycle %lu...\n", sim_time/2);
      fprintf(stderr, "  data_valid_o: %u\n", dut->data_valid_o);
      uint64_t data_o = dut->data_o;
      fprintf(stderr, "  data_o: 0x%016lx\n", data_o);
    }
  }
}

int
main(int argc, char** argv, char** env)
{
  time_t seed = time(NULL);
  srand (seed);
  fprintf(stderr, "INFO: Start RNG seed = %lu.\n", seed);

  Verilated::commandArgs(argc, argv);
  static Vsimon_64_32_core *dut = new Vsimon_64_32_core;

  // run some fixed tests
  while (sim_time < MAX_SIM_TIME)
  {
    dut_reset(dut, sim_time);

    dut->clk ^= 1;
    dut->eval();

    check_out_valid(dut, sim_time);

    if (dut->clk == 1)
    {
      posedge_cnt++;
      switch (posedge_cnt)
      {
      case 10:
        fprintf(stderr, "INFO: Requesting key expansion @ cycle %lu...\n", sim_time/2);
        dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_KEYEXPAND;
        *(uint64_t *)dut->key_i = simon_64_32_key;
        dut->key_valid_i = TRUE;
        break;

      case 12:
        dut->key_valid_i = FALSE;
        break;

      case 160:
        fprintf(stderr, "INFO: Requesting encryption @ cycle %lu...\n", sim_time/2);
        dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_ENCRYPT;
        dut->data_i = simon_64_32_plaintext;
        dut->data_valid_i = TRUE;
        break;

      case 162:
        dut->data_valid_i = FALSE;
        break;

      case 180:
        fprintf(stderr, "INFO: Requesting decryption @ cycle %lu...\n", sim_time/2);
        dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_DECRYPT;
        dut->data_i = simon_64_32_ciphertext;
        dut->data_valid_i = TRUE;
        break;

      case 182:
        dut->data_valid_i = FALSE;
        break;

      }
    }

#ifdef notdef
    fprintf(stderr, "INFO: DUT state @ cycle %lu:\n", sim_time/2);
    fprintf(stderr, "  clk = %u\n", dut->clk);
    fprintf(stderr, "  rst = %u\n", dut->rst);
    fprintf(stderr, "  op_i = %u\n", dut->op_i);
    fprintf(stderr, "  key_valid_i = %u\n", dut->key_valid_i);
    fprintf(stderr, "  data_valid_i = %u\n", dut->data_valid_i);
    fprintf(stderr, "  data_valid_o = %u\n", dut->data_valid_o);
    fprintf(stderr, "  ready_o = %u\n", dut->ready_o);
#endif /* notdef */

    sim_time++;
  }

  // now fuzz the interfaces
  simon_state_t state;
  uint64_t current_key = 0;
  uint64_t trial_cnt = 0;

  // trial stats
  uint64_t n_keyexpand = 0, n_encrypt = 0, n_decrypt = 0, n_end2end = 0;

  vluint64_t sim_snap = sim_time;
  while (trial_cnt < MAX_TRIALS)
  {
    unsigned trialval = rand() % 10000000;

    // only initial computation on the posedge
    if (dut->clk == 0)
    {
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
    }

    // need to enter a trial in the READY_O state
    assert(dut->ready_o);

    if (trial_cnt == 0 || trialval == 17)
    {
      // re-key the ciphers
      fprintf(stderr, "INFO: Fuzzing with a new random key @ cycle %lu...\n", sim_time/2);

      // generate a new random Simon key
      current_key = genrand64();

      // re-key the S/W golden cipher
      simon_64_32_keyexpand(&state, current_key);

      // re-key the Simon H/W core
      dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_KEYEXPAND;
      *(uint64_t *)dut->key_i = current_key;
      dut->key_valid_i = TRUE;

      // execute one cycle
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
      dut->clk ^= 1;
      dut->eval();
      sim_time++;

      // reset request
      dut->key_valid_i = FALSE;

      // wait for the cipher core to be READY_O again
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->ready_o);

      // one more keyexpand
      n_keyexpand++;

      // one more trial finished
      trial_cnt++;
    }

    // encrypt trial if even
    if ((trialval & 1) == 0)
    {
      uint32_t plaintext32, ciphertext32, hw_ciphertext32;
      plaintext32 = genrand32();

      // generate golden truth for this encrpytion trial
      simon_64_32_encrypt(&state, plaintext32, &ciphertext32);

      // test the Simon core H/W
      dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_ENCRYPT;
      dut->data_i = plaintext32;
      dut->data_valid_i = TRUE;

      // execute one cycle
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
      dut->clk ^= 1;
      dut->eval();
      sim_time++;

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->data_valid_o);

      // check the result against the S/W golden model
      hw_ciphertext32 = dut->data_o;
      if (hw_ciphertext32 != ciphertext32)
      {
        fprintf(stderr, "ERROR: encryption mis-match: S/W: 0x%08x, H/W: 0x%08x\n",
                ciphertext32, hw_ciphertext32);
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->ready_o);

      // one more encrypt
      n_encrypt++;

      // one more trial finished
      trial_cnt++;
    }

    // decrypt trial if even
    if ((trialval & 1) == 1)
    {
      uint32_t plaintext32, ciphertext32, hw_plaintext32;
      ciphertext32 = genrand32();

      // generate golden truth for this encrpytion trial
      simon_64_32_decrypt(&state, ciphertext32, &plaintext32);

      // test the Simon core H/W
      dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_DECRYPT;
      dut->data_i = ciphertext32;
      dut->data_valid_i = TRUE;

      // execute one cycle
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
      dut->clk ^= 1;
      dut->eval();
      sim_time++;

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->data_valid_o);

      // check the result against the S/W golden model
      hw_plaintext32 = dut->data_o;
      if (hw_plaintext32 != plaintext32)
      {
        fprintf(stderr, "ERROR: decryption mis-match: S/W: 0x%08x, H/W: 0x%08x\n",
                plaintext32, hw_plaintext32);
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->ready_o);

      // one more decrypt
      n_decrypt++;

      // one more trial finished
      trial_cnt++;
    }

    // encrypt-decrpyt-verify trial
    if ((trialval & 0x3) == 3)
    {
      uint32_t plaintext32, ciphertext32, verif_plaintext32;
      plaintext32 = genrand32();

      // encrypt with the Simon core H/W
      dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_ENCRYPT;
      dut->data_i = plaintext32;
      dut->data_valid_i = TRUE;

      // execute one cycle
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
      dut->clk ^= 1;
      dut->eval();
      sim_time++;

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->data_valid_o);

      // retrieve the result from the H/W cipher core
      ciphertext32 = dut->data_o;

      // wait for the cipher core to be READY_O again
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->ready_o);

      // one more trial finished
      trial_cnt++;

      // test the Simon core H/W
      dut->op_i = Vsimon_64_32_core___024unit::simon_op_e::SIMON_DECRYPT;
      dut->data_i = ciphertext32;
      dut->data_valid_i = TRUE;

      // execute one cycle
      dut->clk ^= 1;
      dut->eval();
      sim_time++;
      dut->clk ^= 1;
      dut->eval();
      sim_time++;

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->data_valid_o);

      // check the result against the S/W golden model
      verif_plaintext32 = dut->data_o;
      if (verif_plaintext32 != plaintext32)
      {
        fprintf(stderr, "ERROR: decryption mis-match: orig: 0x%08x, decrypted: 0x%08x\n",
                plaintext32, verif_plaintext32);
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      do {
        dut->clk ^= 1;
        dut->eval();
        sim_time++;
      } while (!dut->ready_o);

      // one more trial finished
      trial_cnt++;

      // one more decrypt
      n_end2end++;

#ifdef notdef
      fprintf(stderr, "INFO: end2end: plaintext32(0x%08x), ciphertext32(0x%08x), verif_plaintext32(0x%08x)\n",
              plaintext32, ciphertext32, verif_plaintext32);
#endif /* notdef */
    }

    if ((trial_cnt % 1000000) == 0)
      fprintf(stderr, "INFO: Successfully completed %lu trials... (keyexpands:%lu, encrypts:%lu, decrypts:%lu, end2end:%lu) [%.2lf cycles/op]\n",
              trial_cnt, n_keyexpand, n_encrypt, n_decrypt, n_end2end,
              (double)((sim_time - sim_snap)/2) / (double)trial_cnt);
  }
 
  fprintf(stderr, "INFO: Exiting simulation @ cycle %lu...\n", sim_time/2);

  delete dut;
  exit(EXIT_SUCCESS);
}

