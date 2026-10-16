// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// YES if this process was signed with get-task-allow (required for another process to attach a debugger to it).
BOOL F4HasDebugEntitlement(void);

/// Starts the embedded JIT helper extension as its own process and connects to it over XPC.
/// Uses private NSExtension API (fine for sideloading, never for the App Store). Main thread only.
@interface JITExtensionLauncher : NSObject
@property (copy, nullable) void (^failureHandler)(NSString *message);
- (void)startWithHost:(id)host hostProtocol:(Protocol *)hostProtocol workerProtocol:(Protocol *)workerProtocol
           completion:(void (^)(id _Nullable worker, NSError *_Nullable error))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
