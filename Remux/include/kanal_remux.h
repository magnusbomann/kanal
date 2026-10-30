// Repackages a film the system player cannot open into HLS it can.
//
// Built into KanalFFmpeg.framework together with a minimal FFmpeg. Only the
// symbols below are exported, so the FFmpeg inside cannot collide with the
// copy VLCKit carries.
#ifndef KANAL_REMUX_H
#define KANAL_REMUX_H

#ifdef __cplusplus
extern "C" {
#endif

/// Shared between the caller and the remuxing thread. The caller sets
/// `cancel` to stop; everything else is written by the remuxer.
typedef struct {
    /// Set non-zero by the caller to stop. Checked between packets and
    /// inside blocking network reads.
    volatile int cancel;
    /// Length of the whole film in seconds, once known. 0 until then.
    volatile double duration;
    /// Seconds of output written so far, counted from the start position.
    volatile double produced;
    /// Where in the film the output begins, in seconds: the keyframe at or
    /// before the start asked for. Valid once `produced` is above zero.
    volatile double origin;
    /// 1 once the stream has been opened and judged playable.
    volatile int ready;
} kanal_remux_state;

enum {
    KANAL_REMUX_OK = 0,
    KANAL_REMUX_CANCELLED = 1,
    /// The container opened but holds video the system player cannot decode.
    KANAL_REMUX_UNSUPPORTED = 2,
    KANAL_REMUX_OPEN_FAILED = 3,
    KANAL_REMUX_FAILED = 4,
};

/// Reads `url` from `start_seconds` and writes `out_dir/index.m3u8` with
/// fragmented-MP4 segments: video copied, AAC/AC-3/E-AC-3 audio copied, any
/// other audio re-encoded to AAC. Blocks until the film ends, fails or is
/// cancelled — run it on a thread of its own.
///
/// `audio_language` picks the first audio track declaring that language
/// (ISO 639-2), or the default track when NULL or not found.
int kanal_remux_run(const char *url,
                    const char *user_agent,
                    double start_seconds,
                    const char *audio_language,
                    const char *out_dir,
                    kanal_remux_state *state);

#ifdef __cplusplus
}
#endif

#endif
