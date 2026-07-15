#ifndef MediaRemoteShim_h
#define MediaRemoteShim_h

#include <stdbool.h>
#include <stdint.h>

/// Returns the process identifier currently registered with macOS Now Playing,
/// or zero when the owner cannot be resolved quickly and safely.
int32_t JoiCurrentNowPlayingProcessIdentifier(void);

/// Dispatches a transport command to the current macOS Now Playing session.
/// Returns false when the private runtime symbol is unavailable. MediaRemote's
/// command function has no completion result, so true means sent, not confirmed.
bool JoiSendNowPlayingCommand(int32_t command);

/// Returns 1 when the current player explicitly enables the command, 0 when it
/// explicitly does not, and -1 when this private capability query is unavailable.
int32_t JoiNowPlayingCommandSupport(int32_t command);

#endif
