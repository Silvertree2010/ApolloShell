#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

static const char *fixed_value(void) {
    return getenv("APOLLO_FIXED_CLOCK");
}

static double fixed_unix(void) {
    return strtod(fixed_value(), NULL);
}

static int fixed_clock_gettime(clockid_t clock, struct timespec *ts) {
    if (clock == CLOCK_REALTIME && ts && fixed_value()) {
        double t = fixed_unix();
        ts->tv_sec = (time_t)t;
        ts->tv_nsec = (long)((t - (double)ts->tv_sec) * 1e9);
        return 0;
    }
    return clock_gettime(clock, ts);
}

static int fixed_gettimeofday(struct timeval *tv, void *tz) {
    if (!fixed_value()) return gettimeofday(tv, tz);
    if (tv) {
        double t = fixed_unix();
        tv->tv_sec = (time_t)t;
        tv->tv_usec = (int)((t - (double)tv->tv_sec) * 1e6);
    }
    return 0;
}

static CFAbsoluteTime fixed_cf_now(void) {
    if (!fixed_value()) return CFAbsoluteTimeGetCurrent();
    return fixed_unix() - kCFAbsoluteTimeIntervalSince1970;
}

static const char *lookup(const char *list, const char *name, char *value, size_t size) {
    if (!list || !name) return NULL;
    size_t length = strlen(name);
    const char *entry = list;
    while (*entry) {
        const char *end = strchr(entry, ';');
        size_t span = end ? (size_t)(end - entry) : strlen(entry);
        if (span > length && strncmp(entry, name, length) == 0 && entry[length] == '=') {
            size_t n = span - length - 1;
            if (n >= size) n = size - 1;
            memcpy(value, entry + length + 1, n);
            value[n] = 0;
            return value;
        }
        if (!end) break;
        entry = end + 1;
    }
    return NULL;
}

static int answer(void *oldp, size_t *oldlenp, const void *data, size_t needed) {
    if (oldp) {
        if (*oldlenp < needed) return -1;
        memcpy(oldp, data, needed);
    }
    *oldlenp = needed;
    return 0;
}

static int fixed_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    char value[256];
    if (oldlenp && !newp) {
        if (lookup(getenv("APOLLO_FIXED_SYSCTL_STR"), name, value, sizeof value)) {
            return answer(oldp, oldlenp, value, strlen(value) + 1);
        }
        if (lookup(getenv("APOLLO_FIXED_SYSCTL_INT"), name, value, sizeof value)) {
            int32_t number = (int32_t)atoi(value);
            return answer(oldp, oldlenp, &number, sizeof number);
        }
    }
    return sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int fixed_sysctl(int *mib, u_int count, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const char *cpus = getenv("APOLLO_FIXED_CPUS");
    if (cpus && mib && count == 2 && mib[0] == CTL_HW && (mib[1] == HW_NCPU || mib[1] == HW_AVAILCPU) && oldlenp && !newp) {
        int32_t number = (int32_t)atoi(cpus);
        return answer(oldp, oldlenp, &number, sizeof number);
    }
    return sysctl(mib, count, oldp, oldlenp, newp, newlen);
}

typedef struct {
    CFIndex majorVersion;
    CFIndex minorVersion;
    CFIndex patchVersion;
} FixedVersion;

extern FixedVersion _CFOperatingSystemVersionGetCurrent(void);
extern CFStringRef CFCopySystemVersionString(void);

static FixedVersion fixed_os_version(void) {
    const char *value = getenv("APOLLO_FIXED_OS");
    if (!value) return _CFOperatingSystemVersionGetCurrent();
    FixedVersion version = {0, 0, 0};
    sscanf(value, "%ld.%ld.%ld", &version.majorVersion, &version.minorVersion, &version.patchVersion);
    return version;
}

static CFStringRef fixed_os_version_string(void) {
    const char *value = getenv("APOLLO_FIXED_OS_STRING");
    if (!value) return CFCopySystemVersionString();
    return CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
}

extern CFStringRef _CFCopySystemVersionDictionaryValue(CFStringRef key);

static CFStringRef fixed_os_dictionary_value(CFStringRef key) {
    const char *value = getenv("APOLLO_FIXED_OS");
    if (value && key && CFStringCompare(key, CFSTR("ProductVersion"), 0) == kCFCompareEqualTo) {
        return CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
    }
    return _CFCopySystemVersionDictionaryValue(key);
}

static CFTypeRef fixed_registry_property(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator,
                                        IOOptionBits options) {
    const char *cores = getenv("APOLLO_FIXED_GPU_CORES");
    if (cores && key && CFStringCompare(key, CFSTR("gpu-core-count"), 0) == kCFCompareEqualTo) {
        int value = atoi(cores);
        return CFNumberCreate(allocator, kCFNumberIntType, &value);
    }
    return IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}

__attribute__((used)) static struct { const void *replacement; const void *replacee; } interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)fixed_clock_gettime, (const void *)clock_gettime },
    { (const void *)fixed_gettimeofday, (const void *)gettimeofday },
    { (const void *)fixed_cf_now, (const void *)CFAbsoluteTimeGetCurrent },
    { (const void *)fixed_sysctlbyname, (const void *)sysctlbyname },
    { (const void *)fixed_sysctl, (const void *)sysctl },
    { (const void *)fixed_os_version, (const void *)_CFOperatingSystemVersionGetCurrent },
    { (const void *)fixed_os_version_string, (const void *)CFCopySystemVersionString },
    { (const void *)fixed_os_dictionary_value, (const void *)_CFCopySystemVersionDictionaryValue },
    { (const void *)fixed_registry_property, (const void *)IORegistryEntryCreateCFProperty },
};
