#include "SystemMetrics.h"

#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <mach/mach.h>
#include <mach/mach_host.h>

int tm_copy_ifstats(TMIfStats *out, int max_count) {
    if (out == NULL || max_count <= 0) {
        return 0;
    }

    int mib[6] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    size_t len = 0;
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0 || len == 0) {
        return 0;
    }

    char *buf = malloc(len);
    if (buf == NULL) {
        return 0;
    }
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        free(buf);
        return 0;
    }

    int count = 0;
    char *lim = buf + len;
    char *next = buf;
    while (next < lim && count < max_count) {
        struct if_msghdr *ifm = (struct if_msghdr *)next;
        if (ifm->ifm_msglen == 0) {
            break;
        }
        next += ifm->ifm_msglen;
        if (ifm->ifm_type != RTM_IFINFO2) {
            continue;
        }

        struct if_msghdr2 *ifm2 = (struct if_msghdr2 *)ifm;
        struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifm2 + 1);

        TMIfStats *row = &out[count];
        memset(row, 0, sizeof(*row));
        if (sdl->sdl_nlen > 0) {
            size_t n = sdl->sdl_nlen < IFNAMSIZ - 1 ? sdl->sdl_nlen : IFNAMSIZ - 1;
            memcpy(row->name, sdl->sdl_data, n);
            row->name[n] = '\0';
        }
        row->ibytes = ifm2->ifm_data.ifi_ibytes;
        row->obytes = ifm2->ifm_data.ifi_obytes;
        row->ipackets = ifm2->ifm_data.ifi_ipackets;
        row->opackets = ifm2->ifm_data.ifi_opackets;
        row->ierrors = ifm2->ifm_data.ifi_ierrors;
        row->oerrors = ifm2->ifm_data.ifi_oerrors;
        row->up = (ifm2->ifm_flags & IFF_UP) ? 1 : 0;
        row->loopback = (ifm2->ifm_flags & IFF_LOOPBACK) ? 1 : 0;
        row->type = ifm2->ifm_data.ifi_type;
        count++;
    }

    free(buf);
    return count;
}

int tm_cpu_ticks(TMCPUTicks *out, int max_count) {
    if (out == NULL || max_count <= 0) {
        return 0;
    }

    natural_t cpu_count = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_count = 0;
    kern_return_t kr = host_processor_info(
        mach_host_self(),
        PROCESSOR_CPU_LOAD_INFO,
        &cpu_count,
        &info,
        &info_count
    );
    if (kr != KERN_SUCCESS || info == NULL) {
        return 0;
    }

    int n = (int)cpu_count;
    if (n > max_count) {
        n = max_count;
    }
    processor_cpu_load_info_t loads = (processor_cpu_load_info_t)info;
    for (int i = 0; i < n; i++) {
        out[i].user = loads[i].cpu_ticks[CPU_STATE_USER];
        out[i].system = loads[i].cpu_ticks[CPU_STATE_SYSTEM];
        out[i].idle = loads[i].cpu_ticks[CPU_STATE_IDLE];
        out[i].nice = loads[i].cpu_ticks[CPU_STATE_NICE];
    }

    vm_deallocate(mach_task_self(), (vm_address_t)info, info_count * sizeof(natural_t));
    return n;
}
