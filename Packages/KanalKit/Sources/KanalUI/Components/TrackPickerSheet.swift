import KanalCore
import SwiftUI

/// Choosing the audio and subtitle track.
///
/// Matroska files usually carry several of each — an original-language track
/// beside a dubbed one, forced subtitles beside full ones — so this is not a
/// power-user corner. It is the second thing most people reach for.
struct TrackPickerSheet: View {
    let controller: any PlaybackControlling
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if controller.audioTracks.count > 1 {
                    Section(String(UIStrings.audioTrack)) {
                        ForEach(controller.audioTracks) { track in
                            row(
                                title: track.displayName,
                                isSelected: track.id == controller.selectedAudioTrackID
                            ) {
                                controller.selectAudioTrack(track.id)
                            }
                        }
                    }
                }

                if !controller.subtitleTracks.isEmpty {
                    Section(String(UIStrings.subtitles)) {
                        row(
                            title: String(UIStrings.subtitlesOff),
                            isSelected: controller.selectedSubtitleTrackID == nil
                        ) {
                            controller.selectSubtitleTrack(nil)
                        }
                        ForEach(controller.subtitleTracks) { track in
                            row(
                                title: track.displayName,
                                isSelected: track.id == controller.selectedSubtitleTrackID
                            ) {
                                controller.selectSubtitleTrack(track.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(UIStrings.audioAndSubtitles))
            .kanalPlainListBackground()
            .background(KanalColor.background)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(UIStrings.done)) { dismiss() }
                }
            }
            #endif
        }
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationBackground(KanalColor.background)
        #endif
    }

    private func row(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KanalColor.accentSolid)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
