#ifndef MediaRemoteShim_h
#define MediaRemoteShim_h

#include <stdbool.h>
#include <stdint.h>

/// Mirrors MediaRemote's playback-state values while reserving -1 for a
/// runtime/API failure. Keeping the raw state lets Swift distinguish a
/// definitive pause/stop from a temporarily unavailable Now Playing query.
typedef enum JoiNowPlayingPlaybackState {
    JoiNowPlayingPlaybackStateUnavailable = -1,
    JoiNowPlayingPlaybackStateUnknown = 0,
    JoiNowPlayingPlaybackStatePlaying = 1,
    JoiNowPlayingPlaybackStatePaused = 2,
    JoiNowPlayingPlaybackStateStopped = 3,
    JoiNowPlayingPlaybackStateInterrupted = 4,
} JoiNowPlayingPlaybackState;

/// Returns the process identifier currently registered with macOS Now Playing,
/// or zero when the owner cannot be resolved quickly and safely.
int32_t JoiCurrentNowPlayingProcessIdentifier(void);

/// Returns the current Now Playing session's playback state. The modern
/// synchronous request API is preferred; older systems fall back to the
/// callback API with a short timeout. Returns `Unavailable` when neither path
/// produces a trustworthy state quickly.
int32_t JoiCurrentNowPlayingPlaybackState(void);

/// Dispatches a transport command to the current macOS Now Playing session.
/// Returns false when the private runtime symbol is unavailable. MediaRemote's
/// command function has no completion result, so true means sent, not confirmed.
bool JoiSendNowPlayingCommand(int32_t command);

/// Returns 1 when the current player explicitly enables the command, 0 when it
/// explicitly does not, and -1 when this private capability query is unavailable.
int32_t JoiNowPlayingCommandSupport(int32_t command);

#endif
