// aclc: write the MagSafe LED SMC key (ACLC)
// Values: 0 = system, 1 = off, 3 = green, 4 = orange, 6 = slow blink orange, 7 = fast blink orange
// Experimental / untested. Needs sudo.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef struct { char major, minor, build, reserved; uint16_t release; } Vers;
typedef struct { uint16_t version, length; uint32_t cpuP, gpuP, memP; } PLimit;
typedef struct { uint32_t size, type; char attr; } KeyInfo;
typedef struct {
  uint32_t key; Vers vers; PLimit pl; KeyInfo info;
  char result, status, data8; uint32_t data32; uint8_t bytes[32];
} Msg;

static int call(io_connect_t c, Msg *in, Msg *out) {
  size_t n = sizeof(Msg);
  return IOConnectCallStructMethod(c, 2, in, sizeof(Msg), out, &n);
}

int main(int argc, char **argv) {
  if (argc != 2) { fprintf(stderr, "usage: aclc <value>\n"); return 1; }
  uint8_t val = (uint8_t)atoi(argv[1]);
  io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
  io_connect_t c;
  if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &c)) {
    fprintf(stderr, "can't open AppleSMC (try sudo)\n"); return 1;
  }
  Msg in = {0}, out = {0}, out2 = {0};
  in.key = ('A'<<24)|('C'<<16)|('L'<<8)|'C';
  in.data8 = 9;                                  // get key info
  if (call(c, &in, &out)) { fprintf(stderr, "keyinfo failed\n"); return 1; }
  in.info.size = out.info.size;
  in.data8 = 6;                                  // write bytes
  in.bytes[0] = val;
  if (call(c, &in, &out2) || out2.result) {
    fprintf(stderr, "write failed (result %d)\n", out2.result); return 1;
  }
  return 0;
}
