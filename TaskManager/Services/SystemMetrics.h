#ifndef SystemMetrics_h
#define SystemMetrics_h

#include <stdint.h>
#include <net/if.h>

typedef struct {
    char name[IFNAMSIZ];
    uint64_t ibytes;
    uint64_t obytes;
    uint64_t ipackets;
    uint64_t opackets;
    uint64_t ierrors;
    uint64_t oerrors;
    int up;
    int loopback;
    unsigned int type;
} TMIfStats;

int tm_copy_ifstats(TMIfStats *out, int max_count);

typedef struct {
    uint64_t user;
    uint64_t system;
    uint64_t idle;
    uint64_t nice;
} TMCPUTicks;

int tm_cpu_ticks(TMCPUTicks *out, int max_count);

#endif
