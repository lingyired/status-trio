// Standalone research only. This file is not part of any app target.
//
// Read-only probe for the battery panel's power-breakdown rails. It opens one
// short-lived AppleSMC connection, reads only the fixed keys below, dumps the
// AppleSmartBattery PowerOutDetails array, and optionally dims the built-in
// display to show that PDBR tracks the backlight. It never writes SMC keys,
// never requests privileges, and never enumerates the key table.
//
// Build and run:
//   clang -fobjc-arc -framework Foundation -framework IOKit -framework CoreGraphics \
//     -o /tmp/rails scripts/poc/battery-power-rails-readonly.m
//   /tmp/rails 10          # sample for 10 seconds
//   /tmp/rails 20 dim      # sample, dim the display once, restore it
//
// Measured on Mac15,9 (M3 Max, macOS 27.2), adapter attached, display at full
// brightness:
//   PSTR 33.5  PDTR 32.4  PDBR 8.1  PHPC 21.5   residual 2.8 W
//   PDBR at 30% brightness: 0.4 W (responds to backlight, not to load)
//   PHPC under 8 CPU threads: 15 -> 55 W (tracks load, not brightness)
//   PSTR mirrors PDTR one SMC tick later; treat PDTR as the adapter budget.
//   PowerOutDetails is absent with no accessory attached.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

static io_connect_t gConn = 0;

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static double readKey(const char *key) {
    uint8_t req[80] = {0}, res[80] = {0};
    size_t resSize = 80;
    uint32_t word = ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) |
                    ((uint32_t)key[2] << 8) | (uint32_t)key[3];
    req[0] = word & 0xff; req[1] = (word >> 8) & 0xff;
    req[2] = (word >> 16) & 0xff; req[3] = (word >> 24) & 0xff;
    req[42] = 9; // read key info
    if (IOConnectCallStructMethod(gConn, 2, req, 80, res, &resSize) != KERN_SUCCESS || res[40] != 0) return -1;
    uint32_t size = le32(res + 28), type = le32(res + 32);
    uint8_t sizeBytes[4] = { res[28], res[29], res[30], res[31] };
    memset(req, 0, 80); memset(res, 0, 80); resSize = 80;
    req[0] = word & 0xff; req[1] = (word >> 8) & 0xff;
    req[2] = (word >> 16) & 0xff; req[3] = (word >> 24) & 0xff;
    memcpy(req + 28, sizeBytes, 4);
    req[42] = 5; // read bytes (never write command 6)
    if (IOConnectCallStructMethod(gConn, 2, req, 80, res, &resSize) != KERN_SUCCESS || res[40] != 0) return -1;
    if (type == 0x666c7420 && size == 4) { float f; memcpy(&f, res + 48, 4); return f; }
    if (type == 0x73703738 && size == 2) {
        int16_t raw = (int16_t)((res[48] << 8) | res[49]);
        return raw / 256.0;
    }
    return -1;
}

static float displayBrightness(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                          RTLD_LAZY);
    if (!handle) return -1;
    typedef int (*Get)(CGDirectDisplayID, float *);
    typedef int (*Set)(CGDirectDisplayID, float);
    Get get = (Get)dlsym(handle, "DisplayServicesGetBrightness");
    float value = -1;
    if (get) get(CGMainDisplayID(), &value);
    return value;
}

static void setBrightness(float value) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                          RTLD_LAZY);
    if (!handle) return;
    typedef int (*Set)(CGDirectDisplayID, float);
    Set set = (Set)dlsym(handle, "DisplayServicesSetBrightness");
    if (set) set(CGMainDisplayID(), value);
}

static void dumpPowerOut(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery"));
    if (!service) return;
    CFMutableDictionaryRef properties = NULL;
    if (IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS) {
        NSDictionary *registry = (__bridge_transfer NSDictionary *)properties;
        id ports = registry[@"PowerOutDetails"];
        printf("PowerOutDetails: %s\n", ports ? [[ports description] UTF8String] : "(absent)");
    }
    IOObjectRelease(service);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 10;
        BOOL dim = argc > 2 && strcmp(argv[2], "dim") == 0;
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching("AppleSMC"));
        if (!service) { printf("no AppleSMC\n"); return 1; }
        if (IOServiceOpen(service, mach_task_self(), 0, &gConn) != KERN_SUCCESS) { printf("open failed\n"); return 1; }
        dumpPowerOut();
        printf("   t  bright   PDTR   PSTR   PDBR   PHPC    residual\n");
        NSDate *start = [NSDate date];
        BOOL dimmed = NO, restored = NO;
        while ([[NSDate date] timeIntervalSinceDate:start] < seconds) {
            double elapsed = [[NSDate date] timeIntervalSinceDate:start];
            if (dim && !dimmed && elapsed > seconds / 3) { setBrightness(0.30f); dimmed = YES; }
            if (dim && dimmed && !restored && elapsed > seconds * 2 / 3) { setBrightness(1.0f); restored = YES; }
            double input = readKey("PDTR"), system = readKey("PSTR");
            double display = readKey("PDBR"), soc = readKey("PHPC");
            printf("%4.1f   %4.2f %6.2f %6.2f %6.2f %6.2f    %6.2f\n", elapsed, displayBrightness(),
                   input, system, display, soc, input - display - soc);
            usleep(700000);
        }
        if (dim && !restored) setBrightness(1.0f);
        IOServiceClose(gConn);
        IOObjectRelease(service);
    }
    return 0;
}
