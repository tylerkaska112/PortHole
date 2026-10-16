// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
#import "JITExtensionLauncher.h"
#import <objc/message.h>
#import <Security/Security.h>

extern CFTypeRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(CFTypeRef task, CFStringRef name, CFErrorRef *error);

BOOL F4HasDebugEntitlement(void) {
    CFTypeRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return NO;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
    BOOL allowed = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    CFRelease(task);
    return allowed;
}

// Private NSExtension entry points that let an app start one of its OWN embedded extensions on demand.
@interface NSObject (F4PrivateExtension)
+ (id)extensionWithIdentifier:(NSString *)identifier excludingDisabledExtensions:(BOOL)exclude error:(NSError **)error;
- (id)beginExtensionRequestWithInputItems:(NSArray *)items error:(NSError **)error;
- (pid_t)pidForRequestIdentifier:(NSUUID *)request;
- (void)cancelExtensionRequestWithIdentifier:(NSUUID *)request;
@end

@interface JITExtensionLauncher () <NSXPCListenerDelegate>
@property NSXPCListener *listener;
@property NSXPCConnection *connection;
@property id extension;
@property NSUUID *request;
@property id host;
@property Protocol *hostProtocol;
@property Protocol *workerProtocol;
@property(copy) void (^completion)(id, NSError *);
@property pid_t helperPID;
@end

@implementation JITExtensionLauncher

- (void)fail:(NSString *)message {
    if (!self.completion) return;
    void (^callback)(id, NSError *) = self.completion;
    self.completion = nil;
    callback(nil, [NSError errorWithDomain:@"Porthole.JIT" code:1 userInfo:@{NSLocalizedDescriptionKey: message}]);
}

- (void)startWithHost:(id)host hostProtocol:(Protocol *)hostProtocol workerProtocol:(Protocol *)workerProtocol
           completion:(void (^)(id, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"start the helper on the main thread");
    self.host = host; self.hostProtocol = hostProtocol; self.workerProtocol = workerProtocol; self.completion = completion;

    NSURL *url = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"F4JITHelper.appex"];
    NSString *identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
    Class cls = NSClassFromString(@"NSExtension");
    if (!identifier || ![cls respondsToSelector:@selector(extensionWithIdentifier:excludingDisabledExtensions:error:)]) {
        [self fail:@"The JIT helper is missing or this iOS version does not allow starting it."]; return;
    }
    NSError *error = nil;
    self.extension = [cls extensionWithIdentifier:identifier excludingDisabledExtensions:NO error:&error];
    if (!self.extension || ![self.extension respondsToSelector:@selector(beginExtensionRequestWithInputItems:error:)] ||
        ![self.extension respondsToSelector:@selector(pidForRequestIdentifier:)]) {
        [self fail:@"iOS could not load the JIT helper. Check that it was signed together with the app."]; return;
    }
    self.listener = [NSXPCListener anonymousListener];
    self.listener.delegate = self;
    [self.listener resume];

    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{@"F4JITEndpoint": self.listener.endpoint};
    self.request = [self.extension beginExtensionRequestWithInputItems:@[item] error:&error];
    if (!self.request) {
        NSMutableArray *causes = [NSMutableArray array];   // domains and codes only, never raw userInfo
        for (NSError *cause = error; cause && causes.count < 4; cause = cause.userInfo[NSUnderlyingErrorKey])
            [causes addObject:[NSString stringWithFormat:@"%@ (%ld)", cause.domain, (long)cause.code]];
        [self fail:[NSString stringWithFormat:@"iOS refused to start the JIT helper. %@", causes.count ? [causes componentsJoinedByString:@" > "] : @""]];
        return;
    }
    self.helperPID = [self.extension pidForRequestIdentifier:self.request];
    __weak JITExtensionLauncher *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weakSelf fail:@"The JIT helper did not connect. Check that its signing matches the app."];
    });
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Accept exactly one connection, and only from the process we just started.
        if (!self.completion || self.connection || self.helperPID <= 0 || connection.processIdentifier != self.helperPID) {
            [connection invalidate]; return;
        }
        self.connection = connection;
        connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:self.hostProtocol];
        connection.exportedObject = self.host;
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:self.workerProtocol];
        __weak JITExtensionLauncher *weakSelf = self;
        void (^lost)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakSelf.failureHandler) weakSelf.failureHandler(@"The JIT helper connection ended. Relaunch the app before retrying.");
            });
        };
        connection.interruptionHandler = lost;
        connection.invalidationHandler = lost;
        [connection resume];
        id worker = [connection remoteObjectProxy];
        void (^callback)(id, NSError *) = self.completion;
        self.completion = nil;
        callback(worker, nil);
    });
    return YES;
}

- (void)invalidate {
    self.completion = nil;
    [self.connection invalidate]; self.connection = nil;
    [self.listener invalidate]; self.listener = nil;
    if (self.request && [self.extension respondsToSelector:@selector(cancelExtensionRequestWithIdentifier:)])
        [self.extension cancelExtensionRequestWithIdentifier:self.request];
    self.request = nil; self.extension = nil; self.host = nil;
}
@end
