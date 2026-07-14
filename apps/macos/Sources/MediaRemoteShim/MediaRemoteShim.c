#include "MediaRemoteShim.h"

#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>

typedef void (*JoiGetNowPlayingPIDFunction)(dispatch_queue_t, void (^)(int));
typedef id (*JoiObjectMessageFunction)(id, SEL);
typedef int32_t (*JoiIntegerMessageFunction)(id, SEL);

static int32_t JoiModernNowPlayingProcessIdentifier(void) {
    Class requestClass = (Class)objc_getClass("MRNowPlayingRequest");
    if (requestClass == Nil) {
        return 0;
    }

    SEL pathSelector = sel_registerName("localNowPlayingPlayerPath");
    Class requestMetaClass = object_getClass((id)requestClass);
    if (requestMetaClass == Nil ||
        !class_respondsToSelector(requestMetaClass, pathSelector)) {
        return 0;
    }

    JoiObjectMessageFunction objectMessage =
        (JoiObjectMessageFunction)(void *)objc_msgSend;
    id playerPath = objectMessage((id)requestClass, pathSelector);
    if (playerPath == nil) {
        return 0;
    }

    SEL clientSelector = sel_registerName("client");
    if (!class_respondsToSelector(object_getClass(playerPath), clientSelector)) {
        return 0;
    }
    id client = objectMessage(playerPath, clientSelector);
    if (client == nil) {
        return 0;
    }

    SEL pidSelector = sel_registerName("processIdentifier");
    if (!class_respondsToSelector(object_getClass(client), pidSelector)) {
        return 0;
    }
    JoiIntegerMessageFunction integerMessage =
        (JoiIntegerMessageFunction)(void *)objc_msgSend;
    int32_t processIdentifier = integerMessage(client, pidSelector);
    return processIdentifier > 0 ? processIdentifier : 0;
}

int32_t JoiCurrentNowPlayingProcessIdentifier(void) {
    static JoiGetNowPlayingPIDFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // MediaRemote has no public owner-query API on macOS. Loading it at
        // runtime keeps Joi fail-closed if Apple removes or renames the symbol.
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (handle != NULL) {
            function = (JoiGetNowPlayingPIDFunction)dlsym(
                handle,
                "MRMediaRemoteGetNowPlayingApplicationPID"
            );
        }
    });

    int32_t modernProcessIdentifier = JoiModernNowPlayingProcessIdentifier();
    if (modernProcessIdentifier > 0) {
        return modernProcessIdentifier;
    }

    // macOS 14 through early macOS 15 releases support the legacy callback.
    // Newer systems entitlement-gate it, so it is only a runtime fallback.
    if (function == NULL) {
        return 0;
    }

    __block int result = 0;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    function(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(int processIdentifier) {
        result = processIdentifier;
        dispatch_semaphore_signal(semaphore);
    });

    long waitResult = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC)
    );
    return waitResult == 0 && result > 0 ? (int32_t)result : 0;
}
