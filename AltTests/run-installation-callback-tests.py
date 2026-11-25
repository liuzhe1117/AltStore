#!/usr/bin/env python3
"""Exercise the production install callback with synthetic device statuses."""
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--revision", help="Read production code from a git revision")
args = parser.parse_args()
path = "AltServer/Devices/ALTDeviceManager.mm"
source = (subprocess.check_output(["git", "show", f"{args.revision}:{path}"], cwd=root).decode()
          if args.revision else (root / path).read_text())
start = source.index("void ALTDeviceManagerUpdateStatus(plist_t command, plist_t status, void *uuid)\n{")
callback = source[start:source.index("\nvoid ALTDeviceManagerUpdateAppDeletionStatus", start)]
completion = ""
if "void (^completeInstallation)(NSError *)" in source:
    start = source.index("        void (^completeInstallation)(NSError *)")
    completion = source[start:source.index("\n        };", start) + len("\n        };")]

preamble = r'''
#import <Foundation/Foundation.h>
#include <string.h>
typedef NSDictionary *plist_t;
static NSString *AltServerErrorDomain = @"Test.Server";
static NSString *AltServerInstallationErrorDomain = @"Test.Installation";
enum { ALTServerErrorMaximumFreeAppLimitReached = 1, ALTServerErrorUnsupportediOSVersion = 2, ALTServerErrorInstallationFailed = 3 };
static void instproxy_status_get_percent_complete(plist_t s, int *p) { if (s[@"PercentComplete"]) *p = [s[@"PercentComplete"] intValue]; }
static void instproxy_status_get_error(plist_t s, char **n, char **d, uint64_t *c) {
    *c = [s[@"ErrorCode"] unsignedLongLongValue];
    if (s[@"Error"]) *n = strdup([s[@"Error"] UTF8String]);
    if (s[@"ErrorDescription"]) *d = strdup([s[@"ErrorDescription"] UTF8String]);
}
static void instproxy_status_get_name(plist_t s, char **n) { if (s[@"Status"]) *n = strdup([s[@"Status"] UTF8String]); }
@interface ALTDeviceManager : NSObject
@property NSMutableDictionary *installationProgress;
@property NSMutableDictionary *installationCompletionHandlers;
+ (instancetype)sharedManager;
@end
@implementation ALTDeviceManager
+ (instancetype)sharedManager {
    static ALTDeviceManager *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; value.installationProgress = [NSMutableDictionary new]; value.installationCompletionHandlers = [NSMutableDictionary new]; });
    return value;
}
@end
static void check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
'''

main = r'''
int main(void) { @autoreleasepool {
    ALTDeviceManager *manager = ALTDeviceManager.sharedManager;
    NSUUID *uuid = [NSUUID UUID];
    void *key = (void *)uuid.UUIDString.UTF8String;
    __block NSInteger calls = 0;
    __block NSError *result = nil;
    void (^reset)(void) = ^{
        calls = 0; result = nil;
        manager.installationProgress[uuid] = [NSProgress progressWithTotalUnitCount:100];
        manager.installationCompletionHandlers[uuid] = ^(NSError *error) { calls++; result = error; };
    };
    reset();
    ALTDeviceManagerUpdateStatus(nil, @{@"Status": @"Complete"}, key);
    check(calls == 1 && result == nil, @"Complete without preceding progress must finish");
    check([manager.installationProgress[uuid] completedUnitCount] == 100, @"Complete finishes progress");
    reset();
    ALTDeviceManagerUpdateStatus(nil, @{@"Status": @"Installing", @"PercentComplete": @42}, key);
    ALTDeviceManagerUpdateStatus(nil, @{@"Status": @"CreatingSandbox"}, key);
    check(calls == 0, @"A nonterminal status without a percentage must not finish early");
    ALTDeviceManagerUpdateStatus(nil, @{@"Status": @"Complete"}, key);
    check(calls == 1 && result == nil, @"Progress followed by Complete succeeds");
    reset();
    ALTDeviceManagerUpdateStatus(nil, @{@"Error": @"DeviceOSVersionTooLow", @"ErrorCode": @1}, key);
    check(calls == 1 && result.code == ALTServerErrorUnsupportediOSVersion, @"OS error mapping");
    reset();
    ALTDeviceManagerUpdateStatus(nil, @{@"Error": @"ApplicationVerificationFailed"}, key);
    check(calls == 1 && result.code == ALTServerErrorInstallationFailed, @"Named errors finish even without numeric code");
    reset();
    ALTDeviceManagerUpdateStatus(nil, @{@"ErrorCode": @3892346913}, key);
    check(calls == 1 && result.code == ALTServerErrorMaximumFreeAppLimitReached, @"App limit error mapping");
    [manager.installationProgress removeObjectForKey:uuid];
    ALTDeviceManagerUpdateStatus(nil, @{@"Status": @"Complete"}, key);
    check(calls == 1, @"Late status after cleanup is ignored");
'''

if completion:
    main += r'''
    NSLock *completionLock = [NSLock new];
    __block BOOL didComplete = NO;
    __block NSError *installationError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
''' + completion + r'''
    dispatch_apply(64, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t i) {
        completeInstallation(i % 2 ? [NSError errorWithDomain:@"Test" code:1 userInfo:nil] : nil);
    });
    check(didComplete, @"A terminal result is recorded");
    check(dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) == 0, @"Completion wakes the installation queue");
    check(dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0, @"Racing terminal results signal only once");
'''
main += 'NSLog(@"PASS: production status callback and completion-race regressions"); return 0; } }\n'
with tempfile.TemporaryDirectory(prefix="altserver-install-tests-") as directory:
    directory = Path(directory)
    test = directory / "Test.m"
    test.write_text(preamble + callback + main)
    binary = directory / "Test"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", str(test), "-framework", "Foundation", "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
