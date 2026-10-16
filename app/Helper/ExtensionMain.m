// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Entry point of the JIT helper extension.
//
// The host hands the helper an NSXPCListenerEndpoint inside its NSExtensionItem (so the two can talk over XPC). NSExtension decodes its input items
// with a class allow-list that does not include that one class, so decoding fails. We widen the allow-list by exactly one class, NSXPCListenerEndpoint,
// and leave Apple's validation in place for everything else; if the private selector ever changes we refuse to start (fail closed).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void (*originalValidation)(id, SEL, Class, id, BOOL);

static void validateAllowingEndpoint(id decoder, SEL selector, Class cls, id key, BOOL invocations) {
    if (cls == NSXPCListenerEndpoint.class) return;
    originalValidation(decoder, selector, cls, key, invocations);
}

__attribute__((used, visibility("default")))
int NSExtensionMain(int argc, char **argv) {
    Class decoder = NSClassFromString(@"NSXPCDecoder");
    SEL selector = NSSelectorFromString(@"_validateAllowedClass:forKey:allowingInvocations:");
    Method method = class_getInstanceMethod(decoder, selector);
    int (*entry)(int, char **) = dlsym(RTLD_NEXT, "NSExtensionMain");
    if (!method || !entry) return 70;
    originalValidation = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)validateAllowingEndpoint);
    return entry(argc, argv);
}
