#ifndef MediaRemoteShim_h
#define MediaRemoteShim_h

#include <stdint.h>

/// Returns the process identifier currently registered with macOS Now Playing,
/// or zero when the owner cannot be resolved quickly and safely.
int32_t JoiCurrentNowPlayingProcessIdentifier(void);

#endif
