#include <stdlib.h>
#include <iostream>
#include <cstdlib>
#include <verilated.h>
#include "Vsimon_128_128_core.h"
#include "Vsimon_128_128_core___024unit.h"
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

uint128_t simon_128_128_key = GEN128(0x0f0e0d0c0b0a0908, 0x0706050403020100);
uint128_t simon_128_128_plaintext = GEN128(0x6373656420737265, 0x6c6c657661727420);
uint128_t simon_128_128_ciphertext = GEN128(0x49681b1e1e54fe3f, 0x65aa832af84e0bbc);

// generate a random integer
uint64_t
genrand64(void)
{
  return ((uint64_t)random() << 32) ^ (uint64_t)random();
}

uint128_t
genrand128(void)
{
  return (((uint128_t)genrand64()) << 64) | ((uint128_t)genrand64());
}

void
dut_reset (Vsimon_128_128_core *dut, vluint64_t &sim_time)
{
    dut->rst = FALSE;
    if(sim_time >= 3 && sim_time < 6){
        fprintf(stderr, "INFO: Reseting DUT @ cycle %lu...\n", sim_time);
        dut->rst = TRUE;
        dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_IDLE;
        dut->key_valid_i = FALSE;
        dut->data_valid_i = FALSE;
    }
}

void
check_out_valid(Vsimon_128_128_core *dut, vluint64_t &sim_time)
{
  static unsigned char in_valid = 0; //in valid from current cycle
  static unsigned char in_valid_d = 0; //delayed in_valid
  static unsigned char out_valid_exp = 0; //expected out_valid value

  if (sim_time >= VERIF_START_TIME)
  {
    if (dut->data_valid_o)
    {
      fprintf(stderr, "INFO: Request completed @ %lu...\n", sim_time);
      fprintf(stderr, "  data_valid_o: %u\n", dut->data_valid_o);
      uint128_t data_o = *(uint128_t *)dut->data_o.data();
      fprintf(stderr, "  data_o: 0x%016lx:%016lx\n", HI64(data_o), LO64(data_o));
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
  static Vsimon_128_128_core *dut = new Vsimon_128_128_core;

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
        fprintf(stderr, "INFO: Requesting key expansion @ cycle %lu...\n", sim_time);
        dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_KEYEXPAND;
        *(uint128_t *)dut->key_i = simon_128_128_key;
        dut->key_valid_i = TRUE;
        break;

      case 12:
        dut->key_valid_i = FALSE;
        break;

      case 160:
        fprintf(stderr, "INFO: Requesting encryption @ cycle %lu...\n", sim_time);
        dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_ENCRYPT;
        // FIXME: *(uint128_t *)dut->data_i.data() = simon_128_128_plaintext;
        for (unsigned i=0; i < 4; i++)
          dut->data_i.m_storage[i] = ((uint32_t *)&simon_128_128_plaintext)[i];
        dut->data_valid_i = TRUE;
        break;

      case 162:
        dut->data_valid_i = FALSE;
        break;

      case 180:
        fprintf(stderr, "INFO: Requesting decryption @ cycle %lu...\n", sim_time);
        dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_DECRYPT;
        // FIXME: *(uint128_t *)dut->data_i.data() = simon_128_128_ciphertext;
        for (unsigned i=0; i < 4; i++)
          dut->data_i.m_storage[i] = ((uint32_t *)&simon_128_128_ciphertext)[i];
        dut->data_valid_i = TRUE;
        break;

      case 182:
        dut->data_valid_i = FALSE;
        break;

      }
    }

#ifdef notdef
    fprintf(stderr, "INFO: DUT state @ cycle %lu:\n", sim_time);
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
  uint128_t current_key = 0;
  uint64_t trial_cnt = 0;

  // trial stats
  uint64_t n_keyexpand = 0, n_encrypt = 0, n_decrypt = 0;

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
      fprintf(stderr, "INFO: Fuzzing with a new random key @ cycle %lu...\n", sim_time);

      // generate a new random Simon key
      current_key = genrand128();

      // re-key the S/W golden cipher
      simon_128_128_keyexpand(&state, current_key);

      // re-key the Simon H/W core
      dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_KEYEXPAND;
      *(uint128_t *)dut->key_i = current_key;
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
    }

    // encrypt trial if even
    if ((trialval & 1) == 0)
    {
      uint128_t plaintext128, ciphertext128, hw_ciphertext128;
      plaintext128 = genrand128();

      // generate golden truth for this encrpytion trial
      simon_128_128_encrypt(&state, plaintext128, &ciphertext128);

      // test the Simon core H/W
      dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_ENCRYPT;
      *(uint128_t *)dut->data_i.data() = plaintext128;
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
      hw_ciphertext128 = *(uint128_t *)dut->data_o.data();
      if (hw_ciphertext128 != ciphertext128)
      {
        fprintf(stderr, "ERROR: encryption mis-match: S/W: 0x%016lx:%016lx, H/W: 0x%016lx:%016lx\n",
                HI64(ciphertext128), LO64(ciphertext128),
                HI64(hw_ciphertext128), LO64(hw_ciphertext128));
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
    }

    // decrypt trial if even
    if ((trialval & 1) == 1)
    {
      uint128_t plaintext128, ciphertext128, hw_plaintext128;
      ciphertext128 = genrand128();

      // generate golden truth for this encrpytion trial
      simon_128_128_decrypt(&state, ciphertext128, &plaintext128);

      // test the Simon core H/W
      dut->op_i = Vsimon_128_128_core___024unit::simon_op_e::SIMON_DECRYPT;
      *(uint128_t *)dut->data_i.data() = ciphertext128;
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
      hw_plaintext128 = *(uint128_t *)dut->data_o.data();
      if (hw_plaintext128 != plaintext128)
      {
        fprintf(stderr, "ERROR: decryption mis-match: S/W: 0x%016lx:%016lx, H/W: 0x%016lx:%016lx\n",
                HI64(plaintext128), LO64(plaintext128),
                HI64(hw_plaintext128), LO64(hw_plaintext128));
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
    }

    trial_cnt++;
    if ((trial_cnt % 1000000) == 0)
      fprintf(stderr, "INFO: Successfully completed %lu trials... (keyexpands:%lu, encrypts:%lu, decrypts:%lu)\n",
              trial_cnt, n_keyexpand, n_encrypt, n_decrypt);
  }
 
    fprintf(stderr, "INFO: Exiting simulation @ cycle %lu...\n", sim_time);

    delete dut;
    exit(EXIT_SUCCESS);
}

