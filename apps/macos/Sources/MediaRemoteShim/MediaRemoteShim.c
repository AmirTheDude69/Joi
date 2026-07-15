#include "MediaRemoteShim.h"

#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>

typedef void (*JoiGetNowPlayingPIDFunction)(dispatch_queue_t, void (^)(int));
typedef void (*JoiGetNowPlayingPlaybackStateFunction)(
    dispatch_queue_t,
    void (^)(uint32_t)
);
typedef void (*JoiSendCommandFunction)(int32_t, id);
typedef id (*JoiObjectMessageFunction)(id, SEL);
typedef int32_t (*JoiIntegerMessageFunction)(id, SEL);
typedef uint32_t (*JoiUInt32MessageFunction)(id, SEL);
typedef intptr_t (*JoiSignedIntegerMessageFunction)(id, SEL);
typedef unsigned long (*JoiUnsignedIntegerMessageFunction)(id, SEL);
typedef bool (*JoiBooleanMessageFunction)(id, SEL);

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

static int32_t JoiModernNowPlayingPlaybackState(void) {
    Class requestClass = (Class)objc_getClass("MRNowPlayingRequest");
    if (requestClass == Nil) {
        return JoiNowPlayingPlaybackStateUnavailable;
    }

    SEL stateSelector = sel_registerName("localPlaybackState");
    Class requestMetaClass = object_getClass((id)requestClass);
    if (requestMetaClass == Nil ||
        !class_respondsToSelector(requestMetaClass, stateSelector)) {
        return JoiNowPlayingPlaybackStateUnavailable;
    }

    JoiUInt32MessageFunction uint32Message =
        (JoiUInt32MessageFunction)(void *)objc_msgSend;
    uint32_t state = uint32Message((id)requestClass, stateSelector);
    if (state > JoiNowPlayingPlaybackStateInterrupted) {
        return JoiNowPlayingPlaybackStateUnavailable;
    }
    return (int32_t)state;
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

int32_t JoiCurrentNowPlayingPlaybackState(void) {
    int32_t modernState = JoiModernNowPlayingPlaybackState();
    if (modernState != JoiNowPlayingPlaybackStateUnavailable) {
        return modernState;
    }

    static JoiGetNowPlayingPlaybackStateFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (handle != NULL) {
            function = (JoiGetNowPlayingPlaybackStateFunction)dlsym(
                handle,
                "MRMediaRemoteGetNowPlayingApplicationPlaybackState"
            );
        }
    });

    if (function == NULL) {
        return JoiNowPlayingPlaybackStateUnavailable;
    }

    __block int32_t result = JoiNowPlayingPlaybackStateUnavailable;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    function(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(uint32_t state) {
        if (state <= JoiNowPlayingPlaybackStateInterrupted) {
            result = (int32_t)state;
        }
        dispatch_semaphore_signal(semaphore);
    });

    long waitResult = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)
    );
    return waitResult == 0 ? result : JoiNowPlayingPlaybackStateUnavailable;
}

bool JoiSendNowPlayingCommand(int32_t command) {
    static JoiSendCommandFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (handle != NULL) {
            function = (JoiSendCommandFunction)dlsym(
                handle,
                "MRMediaRemoteSendCommand"
            );
        }
    });

    if (function == NULL) {
        return false;
    }
    function(command, nil);
    return true;
}

int32_t JoiNowPlayingCommandSupport(int32_t command) {
    Class requestClass = (Class)objc_getClass("MRNowPlayingRequest");
    if (requestClass == Nil) {
        return -1;
    }

    Class requestMetaClass = object_getClass((id)requestClass);
    SEL supportedSelector = sel_registerName("localSupportedCommands");
    if (requestMetaClass == Nil ||
        !class_respondsToSelector(requestMetaClass, supportedSelector)) {
        return -1;
    }

    JoiObjectMessageFunction objectMessage =
        (JoiObjectMessageFunction)(void *)objc_msgSend;
    id commands = objectMessage((id)requestClass, supportedSelector);
    if (commands == nil) {
        return -1;
    }

    SEL countSelector = sel_registerName("count");
    SEL objectSelector = sel_registerName("objectAtIndex:");
    if (!class_respondsToSelector(object_getClass(commands), countSelector) ||
        !class_respondsToSelector(object_getClass(commands), objectSelector)) {
        return -1;
    }

    JoiUnsignedIntegerMessageFunction unsignedIntegerMessage =
        (JoiUnsignedIntegerMessageFunction)(void *)objc_msgSend;
    typedef id (*JoiObjectAtIndexMessageFunction)(id, SEL, unsigned long);
    JoiObjectAtIndexMessageFunction objectAtIndexMessage =
        (JoiObjectAtIndexMessageFunction)(void *)objc_msgSend;
    JoiSignedIntegerMessageFunction signedIntegerMessage =
        (JoiSignedIntegerMessageFunction)(void *)objc_msgSend;
    JoiBooleanMessageFunction booleanMessage =
        (JoiBooleanMessageFunction)(void *)objc_msgSend;

    unsigned long count = unsignedIntegerMessage(commands, countSelector);
    SEL commandSelector = sel_registerName("command");
    SEL enabledSelector = sel_registerName("isEnabled");
    for (unsigned long index = 0; index < count; index++) {
        id commandInfo = objectAtIndexMessage(commands, objectSelector, index);
        if (commandInfo == nil ||
            !class_respondsToSelector(object_getClass(commandInfo), commandSelector) ||
            !class_respondsToSelector(object_getClass(commandInfo), enabledSelector)) {
            continue;
        }
        intptr_t candidate = signedIntegerMessage(commandInfo, commandSelector);
        if (candidate == command) {
            return booleanMessage(commandInfo, enabledSelector) ? 1 : 0;
        }
    }
    return 0;
}
