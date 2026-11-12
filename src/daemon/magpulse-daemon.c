// magpulse-daemon: Low-level AppleSMC LED controller and PWM pulse engine
// Supports both direct CLI control and background daemon mode with dynamic config reload.

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#include <IOKit/IOKitLib.h>

#define DEFAULT_CONF_PATH "/tmp/magpulse.conf"
#define DEFAULT_FLAG_PATH "/tmp/magpulse.active"
#define ALT_FLAG_PATH     "/tmp/cursor-led.active"
#define ACLC_KEY          (('A'<<24)|('C'<<16)|('L'<<8)|'C')

// ACLC values: 0=system control, 1=off, 3=green, 4=orange/amber, 6=slow blink, 7=fast blink
#define COLOR_AMBER 4
#define COLOR_GREEN 3

typedef struct { char major, minor, build, reserved; uint16_t release; } Vers;
typedef struct { uint16_t version, length; uint32_t cpuP, gpuP, memP; } PLimit;
typedef struct { uint32_t size, type; char attr; } KeyInfo;
typedef struct {
    uint32_t key; Vers vers; PLimit pl; KeyInfo info;
    char result, status, data8; uint32_t data32; uint8_t bytes[32];
} SMCMessage;

typedef struct {
    int active;            // 1 = active, 0 = inactive
    int color;             // 4 = amber, 3 = green
    double period;         // breathing period in seconds (e.g. 2.4)
    int pwm_us;            // PWM slice period in microseconds (e.g. 12000)
    char flagfile[256];    // primary flag file
} MagpulseConfig;

static io_connect_t s_conn = 0;
static uint32_t s_keysize = 0;
static volatile sig_atomic_t s_stop_requested = 0;

static void handle_signal(int sig) {
    (void)sig;
    s_stop_requested = 1;
}

static int smc_call(SMCMessage *in, SMCMessage *out) {
    if (!s_conn) return -1;
    size_t n = sizeof(SMCMessage);
    return IOConnectCallStructMethod(s_conn, 2, in, sizeof(SMCMessage), out, &n);
}

static int smc_init(void) {
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!svc) {
        fprintf(stderr, "[magpulse] Error: AppleSMC service not found (is this an Apple Silicon or Intel Mac with SMC?)\n");
        return -1;
    }
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &s_conn);
    IOObjectRelease(svc);
    if (kr != kIOReturnSuccess || !s_conn) {
        fprintf(stderr, "[magpulse] Error: Failed to open AppleSMC (run with sudo / root privileges)\n");
        return -1;
    }

    SMCMessage in = {0}, out = {0};
    in.key = ACLC_KEY;
    in.data8 = 9; // get key info
    if (smc_call(&in, &out) != 0) {
        fprintf(stderr, "[magpulse] Error: ACLC key query failed\n");
        IOServiceClose(s_conn);
        s_conn = 0;
        return -1;
    }
    s_keysize = out.info.size;
    return 0;
}

static int smc_write(uint8_t val) {
    if (!s_conn || s_keysize == 0) return -1;
    SMCMessage in = {0}, out = {0};
    in.key = ACLC_KEY;
    in.info.size = s_keysize;
    in.data8 = 6; // write bytes
    in.bytes[0] = val;
    return smc_call(&in, &out) || out.result;
}

static void smc_cleanup(void) {
    if (s_conn) {
        smc_write(0); // Restore system control
        IOServiceClose(s_conn);
        s_conn = 0;
    }
}

static double current_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1e9);
}

static void load_config(const char *conf_path, MagpulseConfig *cfg) {
    FILE *fp = fopen(conf_path, "r");
    if (!fp) return;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        char key[64], val[192];
        if (sscanf(line, "%63[^= \t]=%191[^\r\n]", key, val) == 2 ||
            sscanf(line, "%63s %191[^\r\n]", key, val) == 2) {
            if (strcasecmp(key, "active") == 0) {
                cfg->active = atoi(val);
            } else if (strcasecmp(key, "color") == 0) {
                if (strcasecmp(val, "green") == 0 || atoi(val) == 3) {
                    cfg->color = COLOR_GREEN;
                } else {
                    cfg->color = COLOR_AMBER;
                }
            } else if (strcasecmp(key, "period") == 0 || strcasecmp(key, "speed") == 0) {
                double p = atof(val);
                if (p >= 0.3 && p <= 10.0) {
                    cfg->period = p;
                }
            } else if (strcasecmp(key, "pwm") == 0) {
                int pwm = atoi(val);
                if (pwm >= 2000 && pwm <= 30000) {
                    cfg->pwm_us = pwm;
                }
            } else if (strcasecmp(key, "flagfile") == 0) {
                strncpy(cfg->flagfile, val, sizeof(cfg->flagfile) - 1);
                cfg->flagfile[sizeof(cfg->flagfile) - 1] = '\0';
            }
        }
    }
    fclose(fp);
}

static bool check_active(const MagpulseConfig *cfg) {
    if (cfg->active) return true;
    if (cfg->flagfile[0] != '\0' && access(cfg->flagfile, F_OK) == 0) return true;
    if (access(DEFAULT_FLAG_PATH, F_OK) == 0) return true;
    if (access(ALT_FLAG_PATH, F_OK) == 0) return true;
    return false;
}

// Single breath cycle iteration (returns elapsed seconds or false if should stop)
static void run_pulse_cycle(const MagpulseConfig *cfg) {
    double now = current_time_sec();
    double ph = fmod(now, cfg->period) / cfg->period;
    double b = (1.0 - cos(2.0 * M_PI * ph)) / 2.0; // smooth 0..1 curve
    double d = pow(b, 2.2);                         // gamma correction for human eye linearity
    if (d < 0.03) d = 0.03;                         // avoid total dark cutoff

    int on_us = (int)(d * cfg->pwm_us);
    uint8_t color_val = (cfg->color == COLOR_GREEN) ? COLOR_GREEN : COLOR_AMBER;

    smc_write(color_val);
    usleep((useconds_t)on_us);

    if (on_us < cfg->pwm_us) {
        smc_write(1); // turn LED off during remainder of PWM period
        usleep((useconds_t)(cfg->pwm_us - on_us));
    }
}

static int run_daemon_loop(const char *conf_path) {
    MagpulseConfig cfg = {
        .active = 0,
        .color = COLOR_AMBER,
        .period = 2.4,
        .pwm_us = 12000,
        .flagfile = DEFAULT_FLAG_PATH
    };

    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);
    signal(SIGHUP, handle_signal);

    bool was_pulsing = false;
    double last_conf_check = 0;
    time_t pulse_start_time = 0;
    const time_t MAX_PULSE_DURATION = 3600; // 1-hour safety timeout

    printf("[magpulse] Daemon active. Watching %s and flags.\n", conf_path);
    fflush(stdout);

    while (!s_stop_requested) {
        double now = current_time_sec();

        // Refresh config every 0.25 seconds
        if (now - last_conf_check > 0.25) {
            load_config(conf_path, &cfg);
            last_conf_check = now;
        }

        bool is_active = check_active(&cfg);

        if (is_active) {
            if (!was_pulsing) {
                was_pulsing = true;
                pulse_start_time = time(NULL);
            }

            // Check safety timeout
            if (time(NULL) - pulse_start_time > MAX_PULSE_DURATION) {
                fprintf(stderr, "[magpulse] Safety timeout exceeded (60 min). Pausing pulse.\n");
                is_active = false;
            } else {
                run_pulse_cycle(&cfg);
                continue;
            }
        }

        if (was_pulsing) {
            // Transition from active to inactive -> restore system control
            smc_write(0);
            was_pulsing = false;
        }

        // Low-power sleep while idle
        usleep(150000); // 150ms
    }

    smc_write(0);
    printf("[magpulse] Daemon stopped. SMC LED restored to system.\n");
    return 0;
}

static int run_test(int color, double period, double duration_sec) {
    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    MagpulseConfig cfg = {
        .active = 1,
        .color = color,
        .period = period > 0 ? period : 2.0,
        .pwm_us = 12000,
        .flagfile = ""
    };

    printf("[magpulse] Testing MagSafe LED pulse (Color: %s, Period: %.1fs, Duration: %.1fs)...\n",
           color == COLOR_GREEN ? "Green" : "Amber", cfg.period, duration_sec);
    fflush(stdout);

    double start = current_time_sec();
    while (!s_stop_requested && (current_time_sec() - start < duration_sec)) {
        run_pulse_cycle(&cfg);
    }

    smc_write(0);
    printf("[magpulse] Test complete. Restored to system control.\n");
    return 0;
}

static int run_pulse_legacy(const char *flagfile, double period, int pwm_us, int color) {
    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);

    MagpulseConfig cfg = {
        .active = 0,
        .color = color,
        .period = period > 0 ? period : 2.4,
        .pwm_us = pwm_us > 0 ? pwm_us : 12000,
        .flagfile = ""
    };
    if (flagfile) {
        strncpy(cfg.flagfile, flagfile, sizeof(cfg.flagfile) - 1);
    }

    time_t end_time = time(NULL) + 1800;
    while (!s_stop_requested && access(cfg.flagfile, F_OK) == 0 && time(NULL) < end_time) {
        run_pulse_cycle(&cfg);
    }

    smc_write(0);
    return 0;
}

int main(int argc, char **argv) {
    // Check if called as "aclc"
    char *progname = strrchr(argv[0], '/');
    progname = progname ? progname + 1 : argv[0];

    if (strcmp(progname, "aclc") == 0) {
        if (argc != 2) {
            fprintf(stderr, "usage: aclc <value>\n0=system, 1=off, 3=green, 4=orange, 6=slow blink, 7=fast blink\n");
            return 1;
        }
        if (smc_init() != 0) return 1;
        uint8_t val = (uint8_t)atoi(argv[1]);
        int ret = smc_write(val);
        smc_cleanup();
        return ret;
    }

    // Check if called as "aclc-pulse"
    if (strcmp(progname, "aclc-pulse") == 0) {
        const char *flag = argc > 1 ? argv[1] : DEFAULT_FLAG_PATH;
        double period = argc > 2 ? atof(argv[2]) : 2.4;
        int pwm_us = argc > 3 ? atoi(argv[3]) : 12000;
        int color = argc > 4 ? atoi(argv[4]) : COLOR_AMBER;

        if (smc_init() != 0) return 1;
        int ret = run_pulse_legacy(flag, period, pwm_us, color);
        smc_cleanup();
        return ret;
    }

    // Standard magpulse-daemon CLI
    if (argc > 1) {
        if (strcmp(argv[1], "set") == 0 || strcmp(argv[1], "--set") == 0) {
            if (argc < 3) {
                fprintf(stderr, "usage: %s set <0|1|3|4|6|7>\n", argv[0]);
                return 1;
            }
            if (smc_init() != 0) return 1;
            uint8_t val = (uint8_t)atoi(argv[2]);
            int ret = smc_write(val);
            smc_cleanup();
            return ret;
        }

        if (strcmp(argv[1], "test") == 0 || strcmp(argv[1], "--test") == 0) {
            int color = COLOR_AMBER;
            double period = 2.0;
            double duration = 5.0;

            if (argc > 2) {
                if (strcasecmp(argv[2], "green") == 0 || atoi(argv[2]) == 3) {
                    color = COLOR_GREEN;
                }
            }
            if (argc > 3) period = atof(argv[3]);
            if (argc > 4) duration = atof(argv[4]);

            if (smc_init() != 0) return 1;
            int ret = run_test(color, period, duration);
            smc_cleanup();
            return ret;
        }

        if (strcmp(argv[1], "pulse") == 0 || strcmp(argv[1], "--pulse") == 0) {
            const char *flag = argc > 2 ? argv[2] : DEFAULT_FLAG_PATH;
            double period = argc > 3 ? atof(argv[3]) : 2.4;
            int pwm_us = argc > 4 ? atoi(argv[4]) : 12000;
            int color = argc > 5 ? atoi(argv[5]) : COLOR_AMBER;

            if (smc_init() != 0) return 1;
            int ret = run_pulse_legacy(flag, period, pwm_us, color);
            smc_cleanup();
            return ret;
        }

        if (strcmp(argv[1], "daemon") == 0 || strcmp(argv[1], "--daemon") == 0) {
            const char *conf = argc > 2 ? argv[2] : DEFAULT_CONF_PATH;
            if (smc_init() != 0) return 1;
            int ret = run_daemon_loop(conf);
            smc_cleanup();
            return ret;
        }

        if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            printf("Magpulse SMC Engine\n");
            printf("Usage:\n");
            printf("  %s daemon [config_file]         Run background daemon watching config and flag files\n", argv[0]);
            printf("  %s test [amber|green] [period]  Test pulse for 5 seconds\n", argv[0]);
            printf("  %s set <0-7>                    Set raw SMC ACLC key\n", argv[0]);
            printf("  %s pulse [flag] [sec] [pwm] [col] Pulse while flagfile exists\n", argv[0]);
            return 0;
        }
    }

    // Default: run daemon
    if (smc_init() != 0) return 1;
    int ret = run_daemon_loop(DEFAULT_CONF_PATH);
    smc_cleanup();
    return ret;
}
