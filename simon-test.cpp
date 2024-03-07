#include <stdio.h>

#include "simon.h"

//
// test vectors from the Beaulieu paper
//

uint64_t simon_64_32_key = 0x1918111009080100UL;
uint32_t simon_64_32_plaintext = 0x65656877;
uint32_t simon_64_32_ciphertext = 0xc69be9bb;

uint128_t simon_128_64_key = GEN128(0x1b1a191813121110, 0x0b0a090803020100);
uint64_t simon_128_64_plaintext = 0x656b696c20646e75UL;
uint64_t simon_128_64_ciphertext = 0x44c8fc20b9dfa07aUL;

uint128_t simon_128_128_key = GEN128(0x0f0e0d0c0b0a0908, 0x0706050403020100);
uint128_t simon_128_128_plaintext = GEN128(0x6373656420737265, 0x6c6c657661727420);
uint128_t simon_128_128_ciphertext = GEN128(0x49681b1e1e54fe3f, 0x65aa832af84e0bbc);

// run tests from the Beaulieu paper
int
main(void)
{
  simon_state_t state;

  // tests for 64-bit key, 32-bit data
  simon_64_32_keyexpand(&state, simon_64_32_key);

  printf("Test encryption simon_64_32:\n");
  uint32_t ciphertext32;
  simon_64_32_encrypt(&state, simon_64_32_plaintext, &ciphertext32);
  printf("  plaintext:  0x%08x\n", simon_64_32_plaintext);
  printf("  ciphertext: 0x%08x\n", ciphertext32);
  printf("  result: %s\n", (simon_64_32_ciphertext == ciphertext32) ? "pass" : "fail");
 
  printf("Test decryption simon_64_32:\n");
  uint32_t plaintext32;
  simon_64_32_decrypt(&state, simon_64_32_ciphertext, &plaintext32);
  printf("  ciphertext: 0x%08x\n", simon_64_32_ciphertext);
  printf("  plaintext:  0x%08x\n", plaintext32);
  printf("  result: %s\n", (simon_64_32_plaintext == plaintext32) ? "pass" : "fail");
  printf("\n");
 
  // tests for 128-bit key, 64-bit data
  simon_128_64_keyexpand(&state, simon_128_64_key);

  printf("Test encryption simon_128_64:\n");
  uint64_t ciphertext64;
  simon_128_64_encrypt(&state, simon_128_64_plaintext, &ciphertext64);
  printf("  plaintext:  0x%016lx\n", simon_128_64_plaintext);
  printf("  ciphertext: 0x%016lx\n", ciphertext64);
  printf("  result: %s\n", (simon_128_64_ciphertext == ciphertext64) ? "pass" : "fail");
 
  printf("Test decryption simon_128_64:\n");
  uint64_t plaintext64;
  simon_128_64_decrypt(&state, simon_128_64_ciphertext, &plaintext64);
  printf("  ciphertext: 0x%016lx\n", simon_128_64_ciphertext);
  printf("  plaintext:  0x%016lx\n", plaintext64);
  printf("  result: %s\n", (simon_128_64_plaintext == plaintext64) ? "pass" : "fail");
  printf("\n");
 
  // tests for 128-bit key, 128-bit data
  simon_128_128_keyexpand(&state, simon_128_128_key);

  printf("Test encryption simon_128_128:\n");
  uint128_t ciphertext128;
  simon_128_128_encrypt(&state, simon_128_128_plaintext, &ciphertext128);
  printf("  plaintext:  0x%016lx:%016lx\n", HI64(simon_128_128_plaintext), LO64(simon_128_128_plaintext));
  printf("  ciphertext: 0x%016lx:%016lx\n", HI64(ciphertext128), LO64(ciphertext128));
  printf("  result: %s\n", (simon_128_128_ciphertext == ciphertext128) ? "pass" : "fail");
 
  printf("Test decryption simon_128_128:\n");
  uint128_t plaintext128;
  simon_128_128_decrypt(&state, simon_128_128_ciphertext, &plaintext128);
  printf("  ciphertext: 0x%016lx:%016lx\n", HI64(simon_128_128_ciphertext), LO64(simon_128_128_ciphertext));
  printf("  plaintext:  0x%016lx:%016lx\n", HI64(plaintext128), LO64(plaintext128));
  printf("  result: %s\n", (simon_128_128_plaintext == plaintext128) ? "pass" : "fail");
 
  return 0;
}

