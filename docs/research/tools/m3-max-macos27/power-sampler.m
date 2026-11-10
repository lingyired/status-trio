// Standalone read-only research harness. No SMC enumeration or write commands.
// Private IOReport ABI and CLPC descriptors: vladkens/macmon src/sources.rs, src/clpc.rs.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_time.h>
#import <signal.h>
#import <time.h>
#import <math.h>
#import <unistd.h>
#import <errno.h>

extern CFDictionaryRef IOReportCopyAllChannels(uint64_t, uint64_t);
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern void *IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(void *, CFMutableDictionaryRef, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef);
extern uint64_t IOReportChannelGetUnit(CFDictionaryRef);
extern uint64_t IOReportChannelGetChannelID(CFDictionaryRef);
extern uint64_t IOReportChannelGetDriverID(CFDictionaryRef);
extern int IOReportChannelGetFormat(CFDictionaryRef);
extern int IOReportGetChannelCount(CFDictionaryRef);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef, int);
extern int IOReportStateGetCount(CFDictionaryRef);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef, int);
extern int64_t IOReportStateGetResidency(CFDictionaryRef, int);
extern int64_t IOReportStateGetInTransitions(CFDictionaryRef, int);
extern uint64_t IOReportStateGetIDForIndex(CFDictionaryRef, int);

static volatile sig_atomic_t gStop;
static io_connect_t gSMC;
static kern_return_t gSMCOpen;
static io_service_t gBattery, gCLPC;
static NSMutableDictionary *gCLPCInfo;
static void *gSubscription;
static CFMutableDictionaryRef gSubscribed;
static NSMutableDictionary *gPrevious = nil;
static double gPreviousTs;
static NSDictionary *gCLPCOpenInfo;
static NSDateFormatter *gDateFormatter;

static void stopSignal(int sig) { (void)sig; gStop = 1; }
static double mono(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static NSString *hexCode(uint32_t r) { return [NSString stringWithFormat:@"0x%08x", r]; }
static NSString *cfstr(CFStringRef s) { return s ? (__bridge NSString *)s : @""; }
static uint32_t le32(const uint8_t *p) { return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
static NSString *bytesHex(const uint8_t *p, size_t n) { NSMutableString *s=[NSMutableString new]; for(size_t i=0;i<n;i++) [s appendFormat:@"%02x",p[i]]; return s; }
static NSString *fourCC(uint32_t v) { char c[5]={(char)(v>>24),(char)(v>>16),(char)(v>>8),(char)v,0}; return [[NSString alloc] initWithBytes:c length:4 encoding:NSASCIIStringEncoding] ?: @"????"; }
static id jsonSafe(id obj) {
    if (!obj) return [NSNull null];
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]] || obj == [NSNull null]) return obj;
    if ([obj isKindOfClass:[NSData class]]) return @{@"hex":bytesHex([obj bytes],[obj length])};
    if ([obj isKindOfClass:[NSArray class]]) { NSMutableArray *a=[NSMutableArray new]; for(id v in obj) [a addObject:jsonSafe(v)]; return a; }
    if ([obj isKindOfClass:[NSDictionary class]]) { NSMutableDictionary *d=[NSMutableDictionary new]; for(id k in obj) d[[k description]]=jsonSafe(obj[k]); return d; }
    return [obj description];
}
static NSDictionary *props(io_registry_entry_t entry) {
    if(!entry) return @{};
    CFMutableDictionaryRef p=NULL; kern_return_t r=IORegistryEntryCreateCFProperties(entry,&p,kCFAllocatorDefault,0);
    if(r!=0 || !p) return @{@"error":hexCode(r)};
    return CFBridgingRelease(p);
}
static NSDictionary *battery(void) {
    NSDictionary *p=props(gBattery); NSMutableDictionary *b=[NSMutableDictionary new];
    for(NSString *k in @[@"Voltage",@"InstantAmperage",@"Amperage",@"IsCharging",@"ExternalConnected",@"ExternalChargeCapable",@"CurrentCapacity",@"MaxCapacity",@"FullyCharged",@"BatteryInstalled",@"PowerTelemetryData",@"AdapterDetails",@"ChargerData",@"PowerOutDetails"])
        if(p[k]) b[k]=jsonSafe(p[k]);
    b[@"source"]=@"IOKit AppleSmartBattery (pmset-equivalent, no child process)";
    if(!gBattery) b[@"status"]=@"NOT AVAILABLE";
    return b;
}
static NSDictionary *readSMC(NSString *key) {
    NSMutableDictionary *d=[@{@"key":key,@"source":@"AppleSMC selector 2 commands 9 and 5 only",@"unit_inferred":[key hasPrefix:@"T"]?@"°C":@"W",@"unit_basis":[key hasPrefix:@"T"]?@"Stats Modules/Sensors/values.swift M3 mapping; individual sensor, not die average":@"power-key convention; hardware calibration unverified"} mutableCopy];
    if(!gSMC) { d[@"status"]=@"NOT AVAILABLE"; d[@"io_return"]=hexCode(gSMCOpen); return d; }
    const char *k=key.UTF8String; uint32_t word=(uint32_t)k[0]<<24|(uint32_t)k[1]<<16|(uint32_t)k[2]<<8|(uint32_t)k[3];
    uint8_t req[80]={0},res[80]={0}; size_t n=80; memcpy(req,&word,4); req[42]=9;
    kern_return_t r=IOConnectCallStructMethod(gSMC,2,req,80,res,&n);
    d[@"info_io_return"]=hexCode(r); d[@"info_smc_result"]=@(res[40]); d[@"info_smc_status"]=@(res[41]);
    if(r!=0 || res[40]!=0 || n<48) { d[@"status"]=@"read-info failed"; return d; }
    uint32_t size=le32(res+28),type=le32(res+32); d[@"type"]=fourCC(type); d[@"size"]=@(size);
    if(size>32) { d[@"status"]=@"unsupported size (>32)"; return d; }
    memset(req,0,80); memset(res,0,80); n=80; memcpy(req,&word,4); memcpy(req+28,&size,4); req[42]=5;
    r=IOConnectCallStructMethod(gSMC,2,req,80,res,&n); d[@"read_io_return"]=hexCode(r); d[@"read_smc_result"]=@(res[40]); d[@"read_smc_status"]=@(res[41]);
    if(r!=0 || res[40]!=0 || n<48+size) { d[@"status"]=@"read-bytes failed"; return d; }
    const uint8_t *p=res+48; d[@"raw_hex"]=bytesHex(p,size); double val=NAN;
    if(type==0x666c7420 && size==4) { float f; memcpy(&f,p,4); val=f; }
    else if(type==0x73703738 && size==2) val=(int16_t)((p[0]<<8)|p[1])/256.;
    else if(type==0x66706532 && size==2) val=((p[0]<<8)|p[1])/4.;
    else if(type==0x75693820 && size==1) val=p[0];
    else if(type==0x75693136 && size==2) val=(p[0]<<8)|p[1];
    else if(type==0x75693332 && size==4) val=(uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];
    else if(type==0x73693820 && size==1) val=(int8_t)p[0];
    else if(type==0x73693136 && size==2) val=(int16_t)((p[0]<<8)|p[1]);
    if(isfinite(val)) { d[@"value"]=@(val); d[@"status"]=@"ok"; } else { d[@"value"]=[NSNull null]; d[@"status"]=@"read ok; decoder NOT AVAILABLE"; }
    return d;
}
static NSArray *smc(void) { NSMutableArray *a=[NSMutableArray new]; for(NSString *k in @[@"PHPC",@"PZC0",@"PHPS",@"PSTR",@"PDTR",@"PDBR",@"PP0b",@"PPbb",@"PP7b",@"Te05",@"Tf04",@"Tf14"]) [a addObject:readSMC(k)]; return a; }
static BOOL isMainChannel(NSString *name) {
    static NSSet *names; static dispatch_once_t once;
    dispatch_once(&once,^{ names=[NSSet setWithArray:@[@"CPU Energy",@"GPU Energy",@"ANE0",@"DRAM0",@"DISP0",@"DISPEXT0",@"GPU0",@"ISP0",@"AVE0",@"MSR0",@"DCS0",@"AMCC0",@"PCIe Port 0 Energy",@"apciec0 Energy"]]; });
    return [names containsObject:name];
}
static NSMutableDictionary *clpcChannel(uint64_t driver, uint64_t report, NSString *name) {
    int64_t type=1LL|(2LL<<16)|(1LL<<32), unit=(3LL<<56)|(118LL<<32);
    return [@{@"DriverID":@(driver),@"DriverName":@"AppleCLPC",@"IOReportGroupName":@"CLPC",@"IOReportSubGroupName":@"Energy Counters",@"IOReportChannelInfo":@{@"IOReportChannelUnit":@(unit)},@"LegendChannel":@[@(report),@(type),name]} mutableCopy];
}
static NSMutableDictionary *channelMetadata(NSDictionary *ch) {
    CFDictionaryRef c=(__bridge CFDictionaryRef)ch;
    uint64_t driver=IOReportChannelGetDriverID(c), cid=IOReportChannelGetChannelID(c);
    NSString *group=cfstr(IOReportChannelGetGroup(c)),*sub=cfstr(IOReportChannelGetSubGroup(c)),*name=cfstr(IOReportChannelGetChannelName(c)),*unit=[cfstr(IOReportChannelGetUnitLabel(c)) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [@{@"group":group,@"subgroup":sub,@"channel":name,@"unit":unit,@"unit_raw":@(IOReportChannelGetUnit(c)),@"format":@(IOReportChannelGetFormat(c)),@"driver_id":@(driver),@"channel_id":@(cid),@"channel_id_hex":[NSString stringWithFormat:@"0x%016llx",cid],@"id":[NSString stringWithFormat:@"%llu:%llu",driver,cid],@"descriptor_origin":[group isEqual:@"CLPC"]?@"macmon explicit known report ID (not native enumeration)":@"IOReportCopyAllChannels",@"unit_origin":[group isEqual:@"CLPC"]?@"declared by harness from macmon reverse-engineering; getter echoes descriptor, not independent unit proof":@"native IOReport descriptor",@"name_origin":[group isEqual:@"CLPC"]?@"declared by harness from macmon reverse-engineering":@"native IOReport descriptor"} mutableCopy];
}
static void addRawValue(NSMutableDictionary *d, NSDictionary *ch) {
    CFDictionaryRef c=(__bridge CFDictionaryRef)ch;
    int format=[d[@"format"] intValue];
    if(format==1) {
        int64_t v=IOReportSimpleGetIntegerValue(c,0); d[@"raw_count"]=@(v); d[@"raw_count_decimal"]=[NSString stringWithFormat:@"%lld",v];
    } else if(format==2) {
        int count=IOReportStateGetCount(c); NSMutableArray *states=[NSMutableArray new];
        for(int i=0;i<count && i<4096;i++) {
            int64_t v=IOReportStateGetResidency(c,i);
            [states addObject:@{@"name":cfstr(IOReportStateGetNameForIndex(c,i)),@"id":@(IOReportStateGetIDForIndex(c,i)),@"residency":@(v),@"residency_decimal":[NSString stringWithFormat:@"%lld",v],@"in_transitions":@(IOReportStateGetInTransitions(c,i))}];
        }
        d[@"states"]=states;
    } else {
        d[@"value_status"]=@"NOT TESTED: non-simple/non-state format";
        d[@"raw_channel"]=jsonSafe(ch);
    }
}
static NSDictionary *initIOReport(BOOL inventory, BOOL allChannels, NSString *inventoryPath) {
    CFDictionaryRef allCF=IOReportCopyAllChannels(0,0);
    if(!allCF) return @{@"status":@"NOT AVAILABLE: IOReportCopyAllChannels returned NULL"};
    NSMutableDictionary *all=[(__bridge NSDictionary *)allCF mutableCopy];
    NSArray *native=all[@"IOReportChannels"] ?: @[]; NSMutableArray *selected=[NSMutableArray new],*meta=[NSMutableArray new];
    for(NSDictionary *ch in native) {
        NSMutableDictionary *m=channelMetadata(ch); [meta addObject:m];
        if(inventory || allChannels || ([m[@"group"] isEqual:@"Energy Model"] && isMainChannel(m[@"channel"]))) [selected addObject:ch];
    }
    if(gCLPC && [gCLPCInfo[@"CFBundleIdentifier"] isEqual:@"com.apple.driver.AppleT6031CLPC"]) {
        uint64_t driver=0; IORegistryEntryGetRegistryEntryID(gCLPC,&driver);
        [selected addObject:clpcChannel(driver,0x10d81e0084ULL,@"CPU Energy")];
        [selected addObject:clpcChannel(driver,0x191085f98bULL,@"GPU Energy")];
        [selected addObject:clpcChannel(driver,0x18313a3be1ULL,@"ANE")];
    }
    all[@"IOReportChannels"]=selected;
    gSubscription=IOReportCreateSubscription(NULL,(__bridge CFMutableDictionaryRef)all,&gSubscribed,0,NULL);
    NSMutableDictionary *result=[@{@"native_channel_count":@(native.count),@"api_native_channel_count":@(IOReportGetChannelCount(allCF)),@"requested_count":@(selected.count),@"native_channels":meta,@"status":gSubscription && gSubscribed?@"ok":@"NOT AVAILABLE: subscription returned NULL"} mutableCopy];
    if(gSubscribed) result[@"subscribed_count"]=@(IOReportGetChannelCount(gSubscribed));
    if(inventoryPath) {
        if(gSubscription && gSubscribed) {
            CFDictionaryRef sample=IOReportCreateSamples(gSubscription,gSubscribed,NULL);
            NSMutableArray *a=[NSMutableArray new];
            for(NSDictionary *ch in (__bridge NSDictionary *)sample?((__bridge NSDictionary *)sample)[@"IOReportChannels"]:@[]) { NSMutableDictionary *m=channelMetadata(ch); addRawValue(m,ch); [a addObject:m]; }
            result[@"current_samples"]=a;
            if(sample) CFRelease(sample);
        }
        NSData *data=[NSJSONSerialization dataWithJSONObject:jsonSafe(result) options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil]; [data writeToFile:inventoryPath atomically:YES];
    }
    CFRelease(allCF); return result;
}
static NSDictionary *sampleIOReport(double ts) {
    if(!gSubscription || !gSubscribed) return @{@"status":@"NOT AVAILABLE" ,@"channels":@[]};
    double start=mono(); CFDictionaryRef s=IOReportCreateSamples(gSubscription,gSubscribed,NULL); double end=mono();
    if(!s) return @{@"status":@"NOT AVAILABLE: IOReportCreateSamples returned NULL",@"channels":@[]};
    NSMutableArray *channels=[NSMutableArray new]; NSMutableDictionary *next=[NSMutableDictionary new];
    double dt=gPrevious ? ts-gPreviousTs : 0;
    for(NSDictionary *ch in ((__bridge NSDictionary *)s)[@"IOReportChannels"]) {
        NSMutableDictionary *d=channelMetadata(ch); addRawValue(d,ch);
        NSString *ident=d[@"id"]; NSNumber *raw=d[@"raw_count"],*previous=gPrevious[ident]; NSString *unit=d[@"unit"];
        if(raw) {
            next[ident]=raw;
            if(previous && dt>0) {
                int64_t now=raw.longLongValue,prev=previous.longLongValue;
                if(now>=prev) {
                    int64_t delta=now-prev; d[@"delta_count"]=@(delta); d[@"delta_count_decimal"]=[NSString stringWithFormat:@"%lld",delta];
                    d[@"count_status"]=delta==0?@"unchanged this interval":@"increased";
                    double scale=[unit isEqual:@"nJ"]?1e-9:[unit isEqual:@"uJ"]?1e-6:[unit isEqual:@"mJ"]?1e-3:[unit isEqual:@"J"]?1.0:NAN;
                    if(isfinite(scale)) {
                        if(delta>0) { double w=delta*scale/dt; d[@"power_w_estimate"]=@(w); d[@"power_kw_estimate"]=@(w/1000.); }
                        else { d[@"power_w_estimate"]=[NSNull null]; d[@"power_kw_estimate"]=[NSNull null]; d[@"power_status"]=@"count unchanged; zero W not inferred"; }
                    }
                } else { d[@"count_status"]=@"counter decreased/reset; power NOT AVAILABLE"; }
            } else d[@"count_status"]=@"baseline";
        }
        [channels addObject:d];
    }
    gPrevious=next; gPreviousTs=ts; CFRelease(s);
    return @{@"status":@"ok",@"channels":channels,@"interval_s":@(dt),@"read_start_mono":@(start),@"read_end_mono":@(end)};
}
static NSString *thermal(void) {
    switch(NSProcessInfo.processInfo.thermalState) { case NSProcessInfoThermalStateNominal:return @"nominal"; case NSProcessInfoThermalStateFair:return @"fair"; case NSProcessInfoThermalStateSerious:return @"serious"; case NSProcessInfoThermalStateCritical:return @"critical"; default:return @"unknown"; }
}
static void initialize(void) {
    gDateFormatter=[NSDateFormatter new]; gDateFormatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]; gDateFormatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0]; gDateFormatter.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
    if(service) { gSMCOpen=IOServiceOpen(service,mach_task_self(),0,&gSMC); IOObjectRelease(service); } else gSMCOpen=kIOReturnNotFound;
    gBattery=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBattery"));
    gCLPC=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleCLPC"));
    gCLPCInfo=[NSMutableDictionary new]; NSDictionary *p=props(gCLPC);
    for(NSString *k in p) if([k containsString:@"pkg-power-split"] || [@[@"CFBundleIdentifier",@"IOUserClientClass",@"IOClass",@"#clpc-version"] containsObject:k]) gCLPCInfo[k]=jsonSafe(p[k]);
    io_connect_t c=0; kern_return_t r=gCLPC?IOServiceOpen(gCLPC,mach_task_self(),0,&c):kIOReturnNotFound;
    gCLPCOpenInfo=@{@"location":@"IOServiceOpen(AppleCLPC, type=0)",@"io_return":hexCode(r),@"io_return_signed":@((int32_t)r),@"status":r==0?@"open ok; external selectors NOT TESTED":@"NOT AVAILABLE",@"error_string":@((mach_error_string(r)?:"unknown")),@"privilege_attempted":@NO};
    if(c) IOServiceClose(c);
}
static void cleanup(void) { if(gSubscribed) CFRelease(gSubscribed); if(gSubscription) CFRelease(gSubscription); if(gSMC) IOServiceClose(gSMC); if(gBattery) IOObjectRelease(gBattery); if(gCLPC) IOObjectRelease(gCLPC); }
int main(int argc,const char **argv) { @autoreleasepool {
    double hz=1,seconds=60; NSString *out=nil,*label=@"unlabelled",*inventoryPath=nil; BOOL inventory=NO,allChannels=NO;
    for(int i=1;i<argc;i++) {
        if(!strcmp(argv[i],"--hz") && i+1<argc) hz=atof(argv[++i]);
        else if(!strcmp(argv[i],"--seconds") && i+1<argc) seconds=atof(argv[++i]);
        else if(!strcmp(argv[i],"--out") && i+1<argc) out=@(argv[++i]);
        else if(!strcmp(argv[i],"--label") && i+1<argc) label=@(argv[++i]);
        else if(!strcmp(argv[i],"--inventory") && i+1<argc) { inventory=YES; inventoryPath=@(argv[++i]); }
        else if(!strcmp(argv[i],"--all-channels")) allChannels=YES;
        else { fprintf(stderr,"Usage: power-sampler --hz 1 --seconds 60 --out file.jsonl [--label name] [--all-channels] [--inventory channels.json]\n"); return 2; }
    }
    if(!isfinite(hz)||hz<=0||hz>100||!isfinite(seconds)||seconds<=0||!out) { fprintf(stderr,"invalid hz/seconds or missing --out\n"); return 2; }
    FILE *f=fopen(out.fileSystemRepresentation,"w"); if(!f) { perror("out"); return 2; } setvbuf(f,NULL,_IOFBF,65536);
    signal(SIGINT,stopSignal); signal(SIGTERM,stopSignal);
    initialize(); NSDictionary *init=initIOReport(inventory,allChannels,inventoryPath);
    fprintf(stderr,"SMC open=%s; IOReport=%s requested=%s subscribed=%s; CLPC open=%s\n",hexCode(gSMCOpen).UTF8String,[init[@"status"] description].UTF8String,[init[@"requested_count"] description].UTF8String,[init[@"subscribed_count"] description].UTF8String,[gCLPCOpenInfo[@"io_return"] UTF8String]);
    double start=mono(),period=1./hz,prev=0; uint64_t count=0;
    for(uint64_t index=0; !gStop; index++) { @autoreleasepool {
        double deadline=start+index*period; if(deadline>=start+seconds) break;
        while(!gStop && mono()<deadline) { double left=deadline-mono(); if(left<=0) break; struct timespec req={(time_t)left,(long)((left-floor(left))*1e9)}; nanosleep(&req,NULL); }
        if(gStop) break; double ts=mono();
        NSDictionary *io=sampleIOReport(ts); NSMutableArray *clpc=[NSMutableArray new];
        for(NSDictionary *c in io[@"channels"]) if([c[@"group"] isEqual:@"CLPC"]) [clpc addObject:c];
        NSDictionary *cp=props(gCLPC);
        for(NSString *k in cp) if([k containsString:@"pkg-power-split"]) gCLPCInfo[k]=jsonSafe(cp[k]);
        NSMutableDictionary *row=[@{@"schema":@"soc-power-research/1",@"ts_mono":@(ts),@"ts_wall":[gDateFormatter stringFromDate:[NSDate date]],@"label":label,@"index":@(index),@"smc":smc(),@"ioreport":io,@"clpc":@{@"channels":clpc,@"iokit_open":gCLPCOpenInfo,@"properties":gCLPCInfo},@"thermal_state":thermal(),@"pmset_batt":battery(),@"sampling":@{@"target_hz":@(hz),@"scheduled_mono":@(deadline),@"lateness_s":@(ts-deadline),@"interval_s":prev?@(ts-prev):[NSNull null],@"interval_error_s":prev?@(ts-prev-period):[NSNull null]},@"pid":@(getpid())} mutableCopy];
        row[@"sample_read_duration_s"]=@(mono()-ts);
        NSError *error=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:&error];
        if(!data) { fprintf(stderr,"JSON error: %s\n",error.description.UTF8String); gStop=1; break; }
        if(fwrite(data.bytes,1,data.length,f)!=data.length || fputc('\n',f)==EOF) { perror("write"); gStop=1; break; }
        fflush(f); prev=ts; count++;
    }}
    while(!gStop && mono()<start+seconds) { double left=start+seconds-mono(); if(left<=0) break; struct timespec req={(time_t)left,(long)((left-floor(left))*1e9)}; nanosleep(&req,NULL); }
    double elapsed=mono()-start; fclose(f); cleanup(); fprintf(stderr,"samples=%llu elapsed=%.6f seconds stop=%d\n",count,elapsed,gStop); return 0;
}}
