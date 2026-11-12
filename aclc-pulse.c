// aclc-pulse: fake a "breathing" MagSafe LED by software PWM on the ACLC key.
// usage: sudo ./aclc-pulse [flagfile] [period_sec] [pwm_us]
// Runs until flagfile disappears (or 30 min, SIGTERM/SIGINT). Restores LED to system control on exit.
// Experimental / untested.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <IOKit/IOKitLib.h>

typedef struct { char major, minor, build, reserved; uint16_t release; } Vers;
typedef struct { uint16_t version, length; uint32_t cpuP, gpuP, memP; } PLimit;
typedef struct { uint32_t size, type; char attr; } KeyInfo;
typedef struct {
  uint32_t key; Vers vers; PLimit pl; KeyInfo info;
  char result, status, data8; uint32_t data32; uint8_t bytes[32];
} Msg;

static io_connect_t conn;
static uint32_t keysize;
static volatile sig_atomic_t stop_flag;
static void onsig(int s) { (void)s; stop_flag = 1; }

static int call(Msg *in, Msg *out) {
  size_t n = sizeof(Msg);
  return IOConnectCallStructMethod(conn, 2, in, sizeof(Msg), out, &n);
}
static int smc_write(uint8_t v) {
  Msg in = {0}, out = {0};
  in.key = ('A'<<24)|('C'<<16)|('L'<<8)|'C';
  in.info.size = keysize;
  in.data8 = 6;
  in.bytes[0] = v;
  return call(&in, &out) || out.result;
}
static double now(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
  const char *flag = argc > 1 ? argv[1] : "/tmp/cursor-led.active";
  double period = argc > 2 ? atof(argv[2]) : 2.4;
  int pwm_us = argc > 3 ? atoi(argv[3]) : 12000;

  io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
  if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn)) {
    fprintf(stderr, "can't open AppleSMC (try sudo)\n"); return 1;
  }
  Msg in = {0}, out = {0};
  in.key = ('A'<<24)|('C'<<16)|('L'<<8)|'C';
  in.data8 = 9;
  if (call(&in, &out)) { fprintf(stderr, "keyinfo failed\n"); return 1; }
  keysize = out.info.size;

  signal(SIGTERM, onsig); signal(SIGINT, onsig);
  time_t end = time(NULL) + 1800;   // safety timeout

  while (!stop_flag && access(flag, F_OK) == 0 && time(NULL) < end) {
    double ph = fmod(now(), period) / period;
    double b = (1.0 - cos(2.0 * M_PI * ph)) / 2.0;   // 0..1 smooth
    double d = pow(b, 2.2);                          // gamma so it looks linear to the eye
    if (d < 0.03) d = 0.03;
    int on = (int)(d * pwm_us);
    smc_write(4); usleep(on);                        // orange
    if (on < pwm_us) { smc_write(1); usleep(pwm_us - on); }   // off
  }
  smc_write(0);                                      // back to system control
  return 0;
}
