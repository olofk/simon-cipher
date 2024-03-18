#include <stdlib.h>
#include <iostream>
#include <cstdlib>
#include <getopt.h>
#include <verilated.h>
#include "Vsimon_core.h"
#include "Vsimon_core___024unit.h"
#include "simon.h"

// configure the Simon cipher tests to run
#ifndef SIMON_KEY_W
#error ERROR: SIMON_KEY_W is not defined!
#endif
#ifndef SIMON_DATA_W
#error ERROR: SIMON_DATA_W is not defined!
#endif

#define MAX_TRIALS      1000000000UL
#define TRIAL_INTERVAL  500000UL
#define MAX_BUF         64

static uint64_t max_trials = MAX_TRIALS;

#include <stdint.h>
typedef unsigned __int128 uint128_t;
#define HI64(X)        ((uint64_t)(((X) >> 64) & 0xffffffffffffffffULL))
#define LO64(X)        ((uint64_t)(((X))       & 0xffffffffffffffffULL))
#define GEN128(HI, LO) ((((uint128_t)(HI)) << 64) | ((uint128_t)(LO)))
#define TRUE  1
#define FALSE 0

#if (SIMON_DATA_W == 32)
/* cipher data types */
typedef uint64_t simon_key_t;
typedef uint32_t simon_data_t;

/* gold-truth interfaces */
#define SIMON_GT_KEYEXPAND     simon_64_32_keyexpand
#define SIMON_GT_ENCRYPT       simon_64_32_encrypt
#define SIMON_GT_DECRYPT       simon_64_32_decrypt

// reference data, from the Simon paper
uint64_t simon_key = 0x1918111009080100UL;
uint32_t simon_plaintext = 0x65656877;
uint32_t simon_ciphertext = 0xc69be9bb;

char *simon_print_key(char *buf, size_t len, simon_key_t key) { snprintf(buf, len, "0x%016lx", key); return buf; }
char *simon_print_data(char *buf, size_t len, simon_data_t data) { snprintf(buf, len, "0x%08x", data); return buf; }

#elif (SIMON_DATA_W == 64)

/* cipher data types */
typedef uint128_t simon_key_t;
typedef uint64_t simon_data_t;

/* gold-truth interfaces */
#define SIMON_GT_KEYEXPAND     simon_128_64_keyexpand
#define SIMON_GT_ENCRYPT       simon_128_64_encrypt
#define SIMON_GT_DECRYPT       simon_128_64_decrypt

// reference data, from the Simon paper
uint128_t simon_key = GEN128(0x1b1a191813121110, 0x0b0a090803020100);
uint64_t simon_plaintext = 0x656b696c20646e75UL;
uint64_t simon_ciphertext = 0x44c8fc20b9dfa07aUL;

char *simon_print_key(char *buf, size_t len, simon_key_t key) { snprintf(buf, len, "0x%016lx:%016lx", HI64(key), LO64(key)); return buf; }
char *simon_print_data(char *buf, size_t len, simon_data_t data) { snprintf(buf, len, "0x%016lx", data); return buf; }

#elif (SIMON_DATA_W == 128)

/* cipher data types */
typedef uint128_t simon_key_t;
typedef uint128_t simon_data_t;

/* gold-truth interfaces */
#define SIMON_GT_KEYEXPAND     simon_128_128_keyexpand
#define SIMON_GT_ENCRYPT       simon_128_128_encrypt
#define SIMON_GT_DECRYPT       simon_128_128_decrypt

// reference data, from the Simon paper
uint128_t simon_key = GEN128(0x0f0e0d0c0b0a0908, 0x0706050403020100);
uint128_t simon_plaintext = GEN128(0x6373656420737265, 0x6c6c657661727420);
uint128_t simon_ciphertext = GEN128(0x49681b1e1e54fe3f, 0x65aa832af84e0bbc);

char *simon_print_key(char *buf, size_t len, simon_key_t key) { snprintf(buf, len, "0x%016lx:%016lx", HI64(key), LO64(key)); return buf; }
char *simon_print_data(char *buf, size_t len, simon_data_t data) { snprintf(buf, len, "0x%016lx:%016lx", HI64(data), LO64(data)); return buf; }

#else
#error ERROR: Requested Simon configuration not supported!
#endif

//
// Verilator simulation schedulinh helper functions
//

// proceed to the next simulation posedge
#define SIM_GOTO_POSEDGE(DUT, SIM_TIME) \
  if ((DUT)->clk == 0) \
  { \
    (DUT)->clk ^= 1; \
    (DUT)->eval(); \
    (SIM_TIME)++; \
  }

// proceed simulation by N cycles
#define SIM_GOTO_NEXTN(DUT, SIM_TIME, N) \
  for (unsigned __i=0; __i < (N); __i++) \
  { \
    (DUT)->clk ^= 1; \
    (DUT)->eval(); \
    (SIM_TIME)++; \
    (DUT)->clk ^= 1; \
    (DUT)->eval(); \
    (SIM_TIME)++; \
  }

// proceed simulation until PROP is true on a posedge
#define SIM_GOTO_TRUE(DUT, SIM_TIME, PROP) \
  if (!(PROP) || (DUT)->clk == 0) \
    do { \
      (DUT)->clk ^= 1; \
      (DUT)->eval(); \
      (SIM_TIME)++; \
    } while (!(PROP) || ((DUT)->clk == 0));

vluint64_t sim_time = 0;
vluint64_t posedge_cnt = 0;

// trial stats
uint64_t n_keyexpand = 0, n_encrypt = 0, n_encrypt_cl = 0, n_decrypt = 0, n_decrypt_cl = 0, n_end2end = 0;

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
dut_reset (Vsimon_core *dut, vluint64_t &sim_time)
{
    fprintf(stderr, "INFO: Reseting DUT @ cycle %lu...\n", sim_time/2);

    // reset for 3 cycles
    dut->rst = TRUE;
    SIM_GOTO_NEXTN(dut, sim_time, 3);

    // done resetting */
    dut->rst = FALSE;
}

int
main(int argc, char** argv, char** env)
{
  // parse options
  const struct option longopts[] =
  {
    {"maxtrials",   required_argument, 0, 'm'},
    {"help",        no_argument,       0, 'h'},
    {0,0,0,0},
  };

  int index;
  int iarg=0;

  //turn off getopt error message
  opterr=1; 

  while(iarg != -1)
  {
    iarg = getopt_long(argc, argv, "svh", longopts, &index);

    switch (iarg)
    {
      case 'h':
        printf("You hit help...\n");
        break;

      case 'm':
        max_trials = strtoull(optarg, NULL, 10);
        printf("INFO: max trials set to `%lu'...\n", max_trials);
        break;
    }
  }

  simon_state_t state;
  char buf1[MAX_BUF], buf2[MAX_BUF];

  time_t seed = time(NULL);
  srand (seed);
  fprintf(stderr, "INFO: Start RNG seed = %lu.\n", seed);

  Verilated::commandArgs(argc, argv);
  static Vsimon_core *dut = new Vsimon_core;

  // cipher core is in SIMON_IDLE state
  dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_IDLE;
  dut->key_valid_i = FALSE;
  dut->data_valid_i = FALSE;

  // reset the DUTs
  dut_reset(dut, sim_time);
  SIM_GOTO_POSEDGE(dut, sim_time);

  // run some fixed tests
  {
    simon_data_t plaintext, ciphertext;

    // perform key expansion
    fprintf(stderr, "INFO: Requesting key expansion @ cycle %lu...\n", sim_time/2);
    dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_KEYEXPAND;
    *(simon_key_t *)dut->key_i = simon_key;
    // for (unsigned i=0; i < (sizeof(simon_key_t)/sizeof(uint32_t)); i++)
    //   dut->key_i.m_storage[i] = ((uint32_t *)&simon_key)[i];

    dut->key_valid_i = TRUE;

    // execute one cycle
    SIM_GOTO_NEXTN(dut, sim_time, 1);

    // reset request
    dut->key_valid_i = FALSE;

    // wait for the cipher core to be READY_O again
    SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

    SIMON_GT_KEYEXPAND(&state, simon_key);

    // perform an encryption
    fprintf(stderr, "INFO: Requesting encryption @ cycle %lu...\n", sim_time/2);
    dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_ENCRYPT;
    *(simon_data_t *)&dut->data_i = simon_plaintext;
    dut->data_valid_i = TRUE;
  
    // execute one cycle
    SIM_GOTO_NEXTN(dut, sim_time, 1);

    // reset request
    dut->data_valid_i = FALSE;

    // wait for the cipher core to indicate DATA_VALID_O
    SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

    // check the result against the published results
    ciphertext = *(simon_data_t *)&dut->data_o;
    if (ciphertext != simon_ciphertext)
    {
      fprintf(stderr, "ERROR: encryption FAILED: H/W: %s, published: %s\n",
              simon_print_data(buf1, MAX_BUF, ciphertext),
              simon_print_data(buf2, MAX_BUF, simon_ciphertext));
      exit(1);
    }
    else
      fprintf(stderr, "INFO: encryption PASSED: H/W: %s, published: %s\n",
              simon_print_data(buf1, MAX_BUF, ciphertext),
              simon_print_data(buf2, MAX_BUF, simon_ciphertext));
  
    // wait for the cipher core to be READY_O again
    SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

    // perform a decryption
    fprintf(stderr, "INFO: Requesting decryption @ cycle %lu...\n", sim_time/2);
    dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_DECRYPT;
    *(simon_data_t *)&dut->data_i = simon_ciphertext;
    dut->data_valid_i = TRUE;
  
    // execute one cycle
    SIM_GOTO_NEXTN(dut, sim_time, 1);

    // reset request
    dut->data_valid_i = FALSE;

    // wait for the cipher core to indicate DATA_VALID_O
    SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

    // check the result against the published results
    plaintext = *(simon_data_t *)&dut->data_o;
    if (plaintext != simon_plaintext)
    {
      fprintf(stderr, "ERROR: decryption FAILED: H/W: %s, published: %s\n",
              simon_print_data(buf1, MAX_BUF, plaintext),
              simon_print_data(buf2, MAX_BUF, simon_plaintext));
      exit(1);
    }
    else
      fprintf(stderr, "INFO: decryption PASSED: H/W: %s, published: %s\n",
              simon_print_data(buf1, MAX_BUF, plaintext),
              simon_print_data(buf2, MAX_BUF, simon_plaintext));
  
    // wait for the cipher core to be READY_O again
    SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

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

  // now fuzz the interfaces
  simon_key_t current_key = 0;
  uint64_t trial_cnt = 0, trial_since = 0;

  vluint64_t sim_snap = sim_time;
  while (trial_cnt < max_trials)
  {
    unsigned trialval = rand() % 10000000;

    // only initial computation on the posedge
    SIM_GOTO_POSEDGE(dut, sim_time);

    // need to enter a trial in the READY_O state
    assert(dut->ready_o);

    if (trial_cnt == 0 || trialval == 17)
    {
      // re-key the ciphers
      fprintf(stderr, "INFO: Fuzzing with a new random key @ cycle %lu...\n", sim_time/2);

      // generate a new random Simon key
      current_key = (simon_key_t)genrand128();

      // re-key the S/W golden cipher
      SIMON_GT_KEYEXPAND(&state, current_key);

      fprintf(stderr, "INFO: resetting key to `%s'.\n",
              simon_print_key(buf1, MAX_BUF, current_key));

      // re-key the Simon H/W core
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_KEYEXPAND;
      *(simon_key_t *)dut->key_i = current_key;
      dut->key_valid_i = TRUE;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // reset request
      dut->key_valid_i = FALSE;

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more keyexpand
      n_keyexpand++;

      // one more trial finished
      trial_cnt++;
    }

    // encrypt trial if even
    if ((trialval & 1) == 0)
    {
      simon_data_t plaintext, ciphertext, hw_ciphertext;
      plaintext = (simon_data_t)genrand64();

      // generate golden truth for this encrpytion trial
      SIMON_GT_ENCRYPT(&state, plaintext, &ciphertext);

      // test the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_ENCRYPT;
      *(simon_data_t *)&dut->data_i = plaintext;
      dut->data_valid_i = TRUE;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

      // check the result against the S/W golden model
      hw_ciphertext = *(simon_data_t *)&dut->data_o;
      if (hw_ciphertext != ciphertext)
      {
        fprintf(stderr, "ERROR: encryption mis-match: S/W: %s, H/W: %s\n",
                simon_print_data(buf1, MAX_BUF, ciphertext),
                simon_print_data(buf2, MAX_BUF, hw_ciphertext));
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more encrypt
      n_encrypt++;

      // one more trial finished
      trial_cnt++;
    }

    // encrypt_cl trial
    if ((trialval & 0xff) == 1)
    {
      simon_data_t plaintext, ciphertext, hw_ciphertext;
      plaintext = (simon_data_t)genrand64();

      // generate golden truth for this encrpytion trial
      SIMON_GT_ENCRYPT(&state, plaintext, &ciphertext);

      // test the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_ENCRYPT_CL;
      *(simon_data_t *)&dut->data_i = plaintext;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // check the result against the S/W golden model
      hw_ciphertext = *(simon_data_t *)&dut->data_o;
      if (hw_ciphertext != ciphertext)
      {
        fprintf(stderr, "ERROR: encryption mis-match: S/W: %s, H/W: %s\n",
                simon_print_data(buf1, MAX_BUF, ciphertext),
                simon_print_data(buf2, MAX_BUF, hw_ciphertext));
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more encrypt
      n_encrypt_cl++;

      // one more trial finished
      trial_cnt++;
    }

    // decrypt trial if even
    if ((trialval & 1) == 1)
    {
      simon_data_t plaintext, ciphertext, hw_plaintext;
      ciphertext = (simon_data_t)genrand64();

      // generate golden truth for this encrpytion trial
      SIMON_GT_DECRYPT(&state, ciphertext, &plaintext);

      // test the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_DECRYPT;
      *(simon_data_t *)&dut->data_i = ciphertext;
      dut->data_valid_i = TRUE;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

      // check the result against the S/W golden model
      hw_plaintext = *(simon_data_t *)&dut->data_o;
      if (hw_plaintext != plaintext)
      {
        fprintf(stderr, "ERROR: decryption mis-match: S/W: %s, H/W: %s\n",
                simon_print_data(buf1, MAX_BUF, plaintext),
                simon_print_data(buf2, MAX_BUF, hw_plaintext));
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more decrypt
      n_decrypt++;

      // one more trial finished
      trial_cnt++;
    }

    // decrypt_cl trial
    if ((trialval & 0xff) == 2)
    {
      simon_data_t plaintext, ciphertext, hw_plaintext;
      ciphertext = (simon_data_t)genrand64();

      // generate golden truth for this encrpytion trial
      SIMON_GT_DECRYPT(&state, ciphertext, &plaintext);

      // test the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_DECRYPT_CL;
      *(simon_data_t *)&dut->data_i = ciphertext;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // check the result against the S/W golden model
      hw_plaintext = *(simon_data_t *)&dut->data_o;
      if (hw_plaintext != plaintext)
      {
        fprintf(stderr, "ERROR: decryption mis-match: S/W: %s, H/W: %s\n",
                simon_print_data(buf1, MAX_BUF, plaintext),
                simon_print_data(buf2, MAX_BUF, hw_plaintext));
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more decrypt
      n_decrypt_cl++;

      // one more trial finished
      trial_cnt++;
    }

    // encrypt-decrpyt-verify trial
    if ((trialval & 0x3) == 3)
    {
      simon_data_t plaintext, ciphertext, verif_plaintext;
      plaintext = (simon_data_t)genrand64();

      // encrypt with the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_ENCRYPT;
      *(simon_data_t *)&dut->data_i = plaintext;
      dut->data_valid_i = TRUE;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

      // retrieve the result from the H/W cipher core
      ciphertext = *(simon_data_t *)&dut->data_o;

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more trial finished
      trial_cnt++;

      // test the Simon core H/W
      dut->op_i = Vsimon_core___024unit::simon_op_e::SIMON_DECRYPT;
      *(simon_data_t *)&dut->data_i = ciphertext;
      dut->data_valid_i = TRUE;

      // execute one cycle
      SIM_GOTO_NEXTN(dut, sim_time, 1);

      // reset request
      dut->data_valid_i = FALSE;

      // wait for the cipher core to indicate DATA_VALID_O
      SIM_GOTO_TRUE(dut, sim_time, dut->data_valid_o);

      // check the result against the S/W golden model
      verif_plaintext = *(simon_data_t *)&dut->data_o;
      if (verif_plaintext != plaintext)
      {
        fprintf(stderr, "ERROR: decryption mis-match: orig: %s, decrypted: %s\n",
                simon_print_data(buf1, MAX_BUF, plaintext),
                simon_print_data(buf2, MAX_BUF, verif_plaintext));
        exit(1);
      }

      // wait for the cipher core to be READY_O again
      SIM_GOTO_TRUE(dut, sim_time, dut->ready_o);

      // one more trial finished
      trial_cnt++;

      // one more decrypt
      n_end2end++;

  #ifdef notdef
      fprintf(stderr, "INFO: end2end: plaintext32(0x%08x), ciphertext32(0x%08x), verif_plaintext32(0x%08x)\n",
              plaintext, ciphertext, verif_plaintext);
  #endif /* notdef */
    }

    if ((trial_cnt - trial_since) > TRIAL_INTERVAL)
    {
      fprintf(stderr, "INFO: Successfully completed %lu trials... (keyexp:%lu, enc:%lu, enc_cl: %lu, dec:%lu, dec_cl: %lu, end2end:%lu) [%.2lf cycles/op]\n",
              trial_since+TRIAL_INTERVAL, n_keyexpand, n_encrypt, n_encrypt_cl, n_decrypt, n_decrypt_cl, n_end2end,
              (double)((sim_time - sim_snap)/2) / (double)trial_cnt);
      trial_since = trial_since + TRIAL_INTERVAL;
    }
  }
   
  fprintf(stderr, "INFO: Exiting simulation @ cycle %lu...\n", sim_time/2);

  delete dut;
  exit(EXIT_SUCCESS);
}

