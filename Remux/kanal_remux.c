// See kanal_remux.h.
//
// Deliberately a repackager, not a transcoder: the picture is copied byte for
// byte, because re-encoding video on a phone would be slow, hot and lossy.
// Only audio the system player cannot take — DTS above all, common on films —
// is decoded and encoded again, which is cheap.

#include "kanal_remux.h"

#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __attribute__((visibility("default")))

typedef struct {
    AVFormatContext *in;
    AVFormatContext *out;
    int video_in, audio_in;
    int video_out, audio_out;
    // Audio re-encoding, only when the source audio cannot be copied.
    AVCodecContext *decoder;
    AVCodecContext *encoder;
    SwrContext *resampler;
    AVAudioFifo *fifo;
    AVFrame *frame;
    // ADTS AAC, as MPEG-TS carries it, must lose its headers to go in MP4.
    AVBSFContext *audio_filter;
    int64_t next_audio_pts;
    int audio_started;
    // Everything is shifted so output starts at zero at the first keyframe.
    int64_t origin_us;
    int has_origin;
    // Last decode timestamp written per output stream, in that stream's
    // input time base. INT64_MIN until the first.
    int64_t last_dts[2];
    kanal_remux_state *state;
} remux;

static int interrupted(void *opaque) {
    kanal_remux_state *state = opaque;
    return state->cancel != 0;
}

static int copies_audio(enum AVCodecID id) {
    return id == AV_CODEC_ID_AAC || id == AV_CODEC_ID_AC3 || id == AV_CODEC_ID_EAC3;
}

static int pick_audio(AVFormatContext *in, const char *language) {
    if (language && *language) {
        for (unsigned i = 0; i < in->nb_streams; i++) {
            AVStream *s = in->streams[i];
            if (s->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) continue;
            AVDictionaryEntry *tag = av_dict_get(s->metadata, "language", NULL, 0);
            if (tag && strcasecmp(tag->value, language) == 0) return (int)i;
        }
    }
    return av_find_best_stream(in, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
}

static int open_encoder(remux *r, AVStream *in_stream) {
    const AVCodec *decoder = avcodec_find_decoder(in_stream->codecpar->codec_id);
    const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!decoder || !encoder) return -1;

    r->decoder = avcodec_alloc_context3(decoder);
    if (!r->decoder) return -1;
    if (avcodec_parameters_to_context(r->decoder, in_stream->codecpar) < 0) return -1;
    r->decoder->pkt_timebase = in_stream->time_base;
    if (avcodec_open2(r->decoder, decoder, NULL) < 0) return -1;

    r->encoder = avcodec_alloc_context3(encoder);
    if (!r->encoder) return -1;
    // Up to 5.1. Anything wider is folded down rather than refused.
    int channels = r->decoder->ch_layout.nb_channels;
    if (channels > 6) channels = 6;
    if (channels < 1) channels = 2;
    av_channel_layout_default(&r->encoder->ch_layout, channels);
    r->encoder->sample_rate = 48000;
    r->encoder->sample_fmt = AV_SAMPLE_FMT_FLTP;
    r->encoder->bit_rate = channels > 2 ? 384000 : 160000;
    r->encoder->time_base = (AVRational){1, 48000};
    r->encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    if (avcodec_open2(r->encoder, encoder, NULL) < 0) return -1;

    if (swr_alloc_set_opts2(&r->resampler,
                            &r->encoder->ch_layout, r->encoder->sample_fmt, r->encoder->sample_rate,
                            &r->decoder->ch_layout, r->decoder->sample_fmt, r->decoder->sample_rate,
                            0, NULL) < 0) return -1;
    if (swr_init(r->resampler) < 0) return -1;

    r->fifo = av_audio_fifo_alloc(r->encoder->sample_fmt, channels, r->encoder->frame_size * 4);
    r->frame = av_frame_alloc();
    return (r->fifo && r->frame) ? 0 : -1;
}

/// Gives a copied packet a decode timestamp the MP4 muxer will accept.
///
/// Matroska stores presentation times only. The demuxer works decode times
/// out from the frame order, but not for the first few frames of a stream with
/// B-frames — which is every real film — and the muxer refuses a packet
/// without one. Those are placed just before the first known one, the way the
/// encoder had them; a provider stream that jumps backwards is refused rather
/// than patched into nonsense.
/// Returns 0 to write, 1 to drop the packet, -1 to give up.
static int fix_dts(remux *r, AVPacket *packet, AVStream *stream, int slot) {
    int64_t *last = &r->last_dts[slot];
    if (packet->dts == AV_NOPTS_VALUE) {
        if (packet->pts == AV_NOPTS_VALUE) return *last == INT64_MIN ? 1 : (packet->dts = *last + 1, 0);
        if (*last == INT64_MIN) {
            int64_t frame = packet->duration > 0 ? packet->duration : 0;
            if (frame == 0 && stream->avg_frame_rate.num > 0)
                frame = av_rescale_q(1, av_inv_q(stream->avg_frame_rate), stream->time_base);
            int delay = stream->codecpar->video_delay > 0 ? stream->codecpar->video_delay : 0;
            packet->dts = packet->pts - frame * delay;
        } else {
            packet->dts = *last + 1;
        }
    }
    if (*last != INT64_MIN && packet->dts <= *last) {
        int64_t second = av_rescale_q(1, (AVRational){1, 1}, stream->time_base);
        if (*last - packet->dts > second) return -1;
        packet->dts = *last + 1;
    }
    if (packet->pts != AV_NOPTS_VALUE && packet->pts < packet->dts) packet->pts = packet->dts;
    *last = packet->dts;
    return 0;
}

static int write_packet(remux *r, AVPacket *packet) {
    return av_interleaved_write_frame(r->out, packet);
}

/// Drains whole encoder frames from the FIFO. `flush` also sends the tail and
/// tells the encoder the film is over.
static int encode_fifo(remux *r, int flush) {
    int frame_size = r->encoder->frame_size;
    AVPacket *packet = av_packet_alloc();
    if (!packet) return -1;
    int result = 0;

    while (av_audio_fifo_size(r->fifo) >= frame_size || (flush && av_audio_fifo_size(r->fifo) > 0)) {
        int count = FFMIN(av_audio_fifo_size(r->fifo), frame_size);
        AVFrame *frame = av_frame_alloc();
        if (!frame) { result = -1; break; }
        frame->nb_samples = count;
        frame->format = r->encoder->sample_fmt;
        frame->sample_rate = r->encoder->sample_rate;
        av_channel_layout_copy(&frame->ch_layout, &r->encoder->ch_layout);
        if (av_frame_get_buffer(frame, 0) < 0 ||
            av_audio_fifo_read(r->fifo, (void **)frame->data, count) < count) {
            av_frame_free(&frame);
            result = -1;
            break;
        }
        frame->pts = r->next_audio_pts;
        r->next_audio_pts += count;
        result = avcodec_send_frame(r->encoder, frame);
        av_frame_free(&frame);
        if (result < 0) break;
        while ((result = avcodec_receive_packet(r->encoder, packet)) == 0) {
            packet->stream_index = r->audio_out;
            av_packet_rescale_ts(packet, r->encoder->time_base, r->out->streams[r->audio_out]->time_base);
            if ((result = write_packet(r, packet)) < 0) break;
        }
        if (result == AVERROR(EAGAIN)) result = 0;
        if (result < 0) break;
    }
    if (flush && result >= 0) {
        avcodec_send_frame(r->encoder, NULL);
        while (avcodec_receive_packet(r->encoder, packet) == 0) {
            packet->stream_index = r->audio_out;
            av_packet_rescale_ts(packet, r->encoder->time_base, r->out->streams[r->audio_out]->time_base);
            write_packet(r, packet);
        }
    }
    av_packet_free(&packet);
    return result;
}

static int transcode_audio(remux *r, AVPacket *packet, int64_t origin) {
    int result = avcodec_send_packet(r->decoder, packet);
    if (result < 0) return 0; // A damaged audio packet is skipped, not fatal.
    while ((result = avcodec_receive_frame(r->decoder, r->frame)) == 0) {
        if (!r->audio_started) {
            int64_t pts = r->frame->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) pts = origin;
            int64_t relative = av_rescale_q(pts - origin, r->decoder->pkt_timebase, r->encoder->time_base);
            r->next_audio_pts = relative > 0 ? relative : 0;
            r->audio_started = 1;
        }
        int capacity = swr_get_out_samples(r->resampler, r->frame->nb_samples);
        uint8_t **converted = NULL;
        if (av_samples_alloc_array_and_samples(&converted, NULL, r->encoder->ch_layout.nb_channels,
                                               capacity, r->encoder->sample_fmt, 0) < 0) {
            av_frame_unref(r->frame);
            return -1;
        }
        int count = swr_convert(r->resampler, converted, capacity,
                                (const uint8_t **)r->frame->extended_data, r->frame->nb_samples);
        if (count > 0) av_audio_fifo_write(r->fifo, (void **)converted, count);
        av_freep(&converted[0]);
        av_freep(&converted);
        av_frame_unref(r->frame);
        if (count < 0) return -1;
        if (encode_fifo(r, 0) < 0) return -1;
    }
    return 0;
}

/// Writes a copied audio packet, through the ADTS filter when there is one.
static int write_audio(remux *r, AVPacket *packet, AVRational time_base) {
    AVRational out = r->out->streams[r->audio_out]->time_base;
    if (!r->audio_filter) {
        packet->stream_index = r->audio_out;
        av_packet_rescale_ts(packet, time_base, out);
        packet->pos = -1;
        return write_packet(r, packet);
    }
    if (av_bsf_send_packet(r->audio_filter, packet) < 0) return 0;
    int result;
    while ((result = av_bsf_receive_packet(r->audio_filter, packet)) == 0) {
        packet->stream_index = r->audio_out;
        av_packet_rescale_ts(packet, time_base, out);
        packet->pos = -1;
        if (write_packet(r, packet) < 0) return -1;
    }
    return 0;
}

static void close_all(remux *r) {
    if (r->out) {
        if (!(r->out->oformat->flags & AVFMT_NOFILE) && r->out->pb) avio_closep(&r->out->pb);
        avformat_free_context(r->out);
    }
    avformat_close_input(&r->in);
    avcodec_free_context(&r->decoder);
    avcodec_free_context(&r->encoder);
    swr_free(&r->resampler);
    if (r->fifo) av_audio_fifo_free(r->fifo);
    av_frame_free(&r->frame);
    av_bsf_free(&r->audio_filter);
}

EXPORT int kanal_remux_run(const char *url, const char *user_agent, double start_seconds,
                           const char *audio_language, const char *out_dir,
                           kanal_remux_state *state) {
    remux r = {0};
    r.state = state;
    r.video_in = r.audio_in = -1;
    r.last_dts[0] = r.last_dts[1] = INT64_MIN;
    int status = KANAL_REMUX_FAILED;
    AVPacket *packet = NULL;
    AVDictionary *options = NULL;

    av_log_set_level(AV_LOG_ERROR);

    r.in = avformat_alloc_context();
    if (!r.in) return KANAL_REMUX_FAILED;
    r.in->interrupt_callback = (AVIOInterruptCB){interrupted, state};
    if (user_agent) av_dict_set(&options, "user_agent", user_agent, 0);
    // Providers drop long connections; the HTTP layer picks the film back up
    // where it was rather than ending it.
    av_dict_set(&options, "reconnect", "1", 0);
    av_dict_set(&options, "reconnect_streamed", "1", 0);
    av_dict_set(&options, "reconnect_on_network_error", "1", 0);
    av_dict_set(&options, "reconnect_delay_max", "10", 0);
    av_dict_set(&options, "rw_timeout", "20000000", 0);
    int opened = avformat_open_input(&r.in, url, NULL, &options);
    av_dict_free(&options);
    if (opened < 0) {
        // avformat_open_input frees the context on failure.
        return state->cancel ? KANAL_REMUX_CANCELLED : KANAL_REMUX_OPEN_FAILED;
    }
    if (avformat_find_stream_info(r.in, NULL) < 0) {
        status = state->cancel ? KANAL_REMUX_CANCELLED : KANAL_REMUX_OPEN_FAILED;
        goto done;
    }
    if (getenv("KANAL_REMUX_DEBUG")) {
        fprintf(stderr, "kanal_remux: %s, %u streams\n", r.in->iformat->name, r.in->nb_streams);
        av_log_set_level(AV_LOG_INFO);
    }
    if (r.in->duration > 0) state->duration = (double)r.in->duration / AV_TIME_BASE;

    r.video_in = av_find_best_stream(r.in, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (r.video_in < 0) { status = KANAL_REMUX_UNSUPPORTED; goto done; }
    AVStream *video = r.in->streams[r.video_in];
    enum AVCodecID video_codec = video->codecpar->codec_id;
    if (video_codec != AV_CODEC_ID_H264 && video_codec != AV_CODEC_ID_HEVC) {
        status = KANAL_REMUX_UNSUPPORTED;
        goto done;
    }
    r.audio_in = pick_audio(r.in, audio_language);
    int transcodes = r.audio_in >= 0 && !copies_audio(r.in->streams[r.audio_in]->codecpar->codec_id);
    if (transcodes && open_encoder(&r, r.in->streams[r.audio_in]) < 0) {
        // Silence is worse than nothing only marginally; refuse rather than
        // hand the television a film without sound.
        status = KANAL_REMUX_UNSUPPORTED;
        goto done;
    }

    if (start_seconds > 1) {
        int64_t target = (int64_t)(start_seconds * AV_TIME_BASE);
        avformat_seek_file(r.in, -1, INT64_MIN, target, target, AVSEEK_FLAG_BACKWARD);
    }

    char playlist[2048];
    snprintf(playlist, sizeof playlist, "%s/index.m3u8", out_dir);
    if (avformat_alloc_output_context2(&r.out, NULL, "hls", playlist) < 0 || !r.out) goto done;

    AVStream *video_out = avformat_new_stream(r.out, NULL);
    if (!video_out || avcodec_parameters_copy(video_out->codecpar, video->codecpar) < 0) goto done;
    // Apple only plays HEVC tagged hvc1, and refuses the hev1 FFmpeg defaults to.
    video_out->codecpar->codec_tag = video_codec == AV_CODEC_ID_HEVC ? MKTAG('h', 'v', 'c', '1') : 0;
    video_out->time_base = video->time_base;
    r.video_out = video_out->index;

    if (r.audio_in >= 0) {
        AVStream *audio_out = avformat_new_stream(r.out, NULL);
        if (!audio_out) goto done;
        if (transcodes) {
            if (avcodec_parameters_from_context(audio_out->codecpar, r.encoder) < 0) goto done;
            audio_out->time_base = r.encoder->time_base;
        } else {
            AVStream *audio = r.in->streams[r.audio_in];
            if (audio->codecpar->codec_id == AV_CODEC_ID_AAC && audio->codecpar->extradata_size == 0) {
                const AVBitStreamFilter *filter = av_bsf_get_by_name("aac_adtstoasc");
                if (!filter || av_bsf_alloc(filter, &r.audio_filter) < 0) goto done;
                if (avcodec_parameters_copy(r.audio_filter->par_in, audio->codecpar) < 0) goto done;
                r.audio_filter->time_base_in = audio->time_base;
                if (av_bsf_init(r.audio_filter) < 0) goto done;
                if (avcodec_parameters_copy(audio_out->codecpar, r.audio_filter->par_out) < 0) goto done;
            } else if (avcodec_parameters_copy(audio_out->codecpar, audio->codecpar) < 0) goto done;
            audio_out->codecpar->codec_tag = 0;
            audio_out->time_base = r.in->streams[r.audio_in]->time_base;
        }
        r.audio_out = audio_out->index;
    }

    char segments[2048];
    snprintf(segments, sizeof segments, "%s/segment%%05d.m4s", out_dir);
    av_dict_set(&options, "hls_segment_type", "fmp4", 0);
    av_dict_set(&options, "hls_fmp4_init_filename", "init.mp4", 0);
    av_dict_set(&options, "hls_segment_filename", segments, 0);
    av_dict_set(&options, "hls_time", "4", 0);
    av_dict_set(&options, "hls_list_size", "0", 0);
    av_dict_set(&options, "hls_playlist_type", "event", 0);
    // temp_file: a segment appears under its name only once complete, so the
    // television never fetches half of one.
    av_dict_set(&options, "hls_flags", "independent_segments+temp_file", 0);
    int header = avformat_write_header(r.out, &options);
    av_dict_free(&options);
    if (header < 0) goto done;

    packet = av_packet_alloc();
    if (!packet) goto done;
    state->ready = 1;

    for (;;) {
        if (state->cancel) { status = KANAL_REMUX_CANCELLED; break; }
        int read = av_read_frame(r.in, packet);
        if (read == AVERROR_EOF) { status = KANAL_REMUX_OK; break; }
        if (read < 0) { status = state->cancel ? KANAL_REMUX_CANCELLED : KANAL_REMUX_FAILED; break; }

        AVStream *in_stream = r.in->streams[packet->stream_index];
        int64_t ts = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;

        if (packet->stream_index == r.video_in) {
            // Output begins at the first keyframe, at zero.
            if (!r.has_origin) {
                if (!(packet->flags & AV_PKT_FLAG_KEY) || ts == AV_NOPTS_VALUE) { av_packet_unref(packet); continue; }
                r.origin_us = av_rescale_q(ts, in_stream->time_base, AV_TIME_BASE_Q);
                r.has_origin = 1;
                int64_t first = r.in->start_time != AV_NOPTS_VALUE ? r.in->start_time : 0;
                state->origin = (double)(r.origin_us - first) / AV_TIME_BASE;
            }
            int64_t origin = av_rescale_q(r.origin_us, AV_TIME_BASE_Q, in_stream->time_base);
            if (packet->pts != AV_NOPTS_VALUE) packet->pts -= origin;
            if (packet->dts != AV_NOPTS_VALUE) packet->dts -= origin;
            int fixed = fix_dts(&r, packet, in_stream, 0);
            if (fixed < 0) { status = KANAL_REMUX_FAILED; break; }
            if (fixed > 0) { av_packet_unref(packet); continue; }
            if (packet->pts != AV_NOPTS_VALUE) {
                double seconds = packet->pts * av_q2d(in_stream->time_base);
                if (seconds > state->produced) state->produced = seconds;
            }
            packet->stream_index = r.video_out;
            av_packet_rescale_ts(packet, in_stream->time_base, r.out->streams[r.video_out]->time_base);
            packet->pos = -1;
            if (write_packet(&r, packet) < 0) { status = KANAL_REMUX_FAILED; break; }
        } else if (packet->stream_index == r.audio_in && r.has_origin) {
            int64_t origin = av_rescale_q(r.origin_us, AV_TIME_BASE_Q, in_stream->time_base);
            if (ts == AV_NOPTS_VALUE || ts < origin) { av_packet_unref(packet); continue; }
            if (transcodes) {
                if (transcode_audio(&r, packet, origin) < 0) { status = KANAL_REMUX_FAILED; break; }
            } else {
                if (packet->pts != AV_NOPTS_VALUE) packet->pts -= origin;
                if (packet->dts != AV_NOPTS_VALUE) packet->dts -= origin;
                int fixed = fix_dts(&r, packet, in_stream, 1);
                if (fixed < 0) { status = KANAL_REMUX_FAILED; break; }
                if (fixed > 0) { av_packet_unref(packet); continue; }
                if (write_audio(&r, packet, in_stream->time_base) < 0) { status = KANAL_REMUX_FAILED; break; }
            }
        }
        av_packet_unref(packet);
    }

    if (status == KANAL_REMUX_OK && transcodes) encode_fifo(&r, 1);
    // Written even when cancelled, so the playlist is closed off cleanly.
    av_write_trailer(r.out);

done:
    av_packet_free(&packet);
    close_all(&r);
    return status;
}
