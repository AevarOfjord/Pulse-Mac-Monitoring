#include "ProcessSupport.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <string.h>
#include <unistd.h>

int pulse_list_pids(int32_t *buffer, int capacity) {
    if (!buffer) return proc_listallpids(NULL, 0);
    return proc_listallpids(buffer, capacity * (int)sizeof(int32_t));
}

int pulse_read_process(int32_t pid, PulseProcessInfo *info) {
    memset(info, 0, sizeof(*info));
    struct proc_bsdinfo bsd = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return 0;
    info->pid = pid;
    info->parent_pid = bsd.pbi_ppid;
    info->uid = bsd.pbi_uid;
    info->started_microseconds = bsd.pbi_start_tvsec * 1000000 + bsd.pbi_start_tvusec;
    strlcpy(info->name, bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm, sizeof(info->name));
    proc_pidpath(pid, info->path, sizeof(info->path));
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
        info->has_usage = 1;
        info->has_resident = 1;
        // rusage CPU counters use Mach absolute-time units on Apple silicon.
        // XNU: osfmk/kern/bsd_kern.c fill_task_rusage -> task_power_info_locked.
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        __uint128_t nanos = ((__uint128_t)usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom;
        info->cpu_nanoseconds = nanos > UINT64_MAX ? UINT64_MAX : (uint64_t)nanos;
        info->resident_bytes = usage.ri_resident_size;
        info->footprint_bytes = usage.ri_phys_footprint;
        info->peak_footprint_bytes = usage.ri_lifetime_max_phys_footprint;
    } else {
        struct proc_taskinfo task = {0};
        if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
            info->resident_bytes = task.pti_resident_size;
            info->has_resident = 1;
        }
    }
    // Reading another app's task VM requires access that ordinary apps may
    // not have. Never infer compressed bytes by subtracting RSS from footprint.
    if (pid == getpid()) {
        task_vm_info_data_t vm = {0};
        mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) == KERN_SUCCESS) {
            info->compressed_bytes = vm.compressed;
            info->has_compressed = 1;
        }
    }
    return 1;
}

int pulse_read_arguments(int32_t pid, char *buffer, int capacity) {
    int mib[] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = (size_t)capacity;
    if (sysctl(mib, 3, buffer, &size, NULL, 0) != 0) return 0;
    return (int)size;
}
