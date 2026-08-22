import KanalCore
import SwiftUI

/// The TV guide: channels down, time across.
///
/// Both axes scroll, but the channel column and the hour header must stay put
/// — a guide where you lose track of which row you are on is useless. Rather
/// than synchronising several scroll views, this reads the single scroll's
/// offset and pushes the two headers back by the same amount, so they appear
/// pinned while everything stays in one lazily-drawn grid.
public struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator

    /// How far back and forward the timeline runs from now.
    private let hoursBefore: Double = 1
    private let hoursAfter: Double = 12

    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var selected: Programme?
    @State private var now = Date.now

    public init() {}

    public var body: some View {
        Group {
            if model.guide == nil {
                EmptyStateView(
                    symbol: "calendar.badge.clock",
                    title: String(UIStrings.guideMissingTitle),
                    message: String(UIStrings.guideMissingBody)
                )
            } else if channels.isEmpty {
                EmptyStateView(
                    symbol: "calendar.badge.clock",
                    title: String(UIStrings.guideNoChannelsTitle),
                    message: String(UIStrings.guideNoChannelsBody)
                )
            } else {
                grid
            }
        }
        .background(KanalColor.background)
        .sheet(item: $selected) { programme in
            ProgrammeSheet(programme: programme, channel: channel(for: programme))
        }
        // The now-line has to keep up without redrawing the whole grid.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                rows
                    .padding(.leading, channelColumnWidth)
                    .padding(.top, headerHeight)

                nowLine
                    .padding(.leading, channelColumnWidth)
                    .padding(.top, headerHeight)

                // Pushed back by the scroll offset so they read as pinned.
                hourHeader
                    .padding(.leading, channelColumnWidth)
                    .offset(y: verticalOffset)

                channelColumn
                    .padding(.top, headerHeight)
                    .offset(x: horizontalOffset)

                // The corner sits above both, or the two would cross it.
                Color.clear
                    .frame(width: channelColumnWidth, height: headerHeight)
                    .background(KanalColor.background)
                    .offset(x: horizontalOffset, y: verticalOffset)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGPoint.self) { geometry in
            CGPoint(x: geometry.contentOffset.x, y: geometry.contentOffset.y)
        } action: { _, offset in
            horizontalOffset = max(offset.x, 0)
            verticalOffset = max(offset.y, 0)
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(channels) { channel in
                GuideRow(
                    programmes: programmes(for: channel),
                    timelineStart: timelineStart,
                    hourWidth: hourWidth,
                    rowHeight: rowHeight,
                    now: now,
                    onSelect: { selected = $0 },
                    onPlay: { navigator.play(channel) }
                )
                .frame(width: timelineWidth, height: rowHeight, alignment: .leading)
            }
        }
    }

    private var channelColumn: some View {
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(channels) { channel in
                Button {
                    navigator.play(channel)
                } label: {
                    HStack(spacing: KanalMetrics.sm) {
                        Artwork(
                            url: channel.logoURL, title: channel.title,
                            symbol: "tv", contentMode: .fit
                        )
                        .frame(width: rowHeight * 0.7, height: rowHeight * 0.7)
                        .background(KanalColor.surface)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))

                        Text(channel.title)
                            .font(KanalFont.body(13))
                            .foregroundStyle(KanalColor.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, KanalMetrics.sm)
                    .frame(width: channelColumnWidth, height: rowHeight, alignment: .leading)
                    .background(KanalColor.background)
                }
                .buttonStyle(KanalCardButtonStyle())
            }
        }
    }

    private var hourHeader: some View {
        HStack(spacing: 0) {
            ForEach(hourMarks, id: \.self) { date in
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(KanalFont.caption(11))
                    .foregroundStyle(KanalColor.secondaryText)
                    .frame(width: hourWidth, alignment: .leading)
                    .padding(.leading, KanalMetrics.xs)
            }
        }
        .frame(height: headerHeight, alignment: .leading)
        .background(KanalColor.background)
    }

    private var nowLine: some View {
        Rectangle()
            .fill(KanalColor.live)
            .frame(width: 2, height: CGFloat(channels.count) * (rowHeight + rowSpacing))
            .offset(x: xPosition(for: now))
            .allowsHitTesting(false)
    }

    // MARK: Geometry

    private var timelineStart: Date {
        // Anchored to the hour so the header reads as clock times.
        let anchored = now.addingTimeInterval(-hoursBefore * 3600)
        return Calendar.current.date(
            bySetting: .minute, value: 0, of: anchored
        ) ?? anchored
    }

    private var timelineWidth: CGFloat {
        CGFloat(hoursBefore + hoursAfter) * hourWidth
    }

    private var hourMarks: [Date] {
        stride(from: 0.0, to: hoursBefore + hoursAfter, by: 1.0).map {
            timelineStart.addingTimeInterval($0 * 3600)
        }
    }

    private func xPosition(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(timelineStart) / 3600) * hourWidth
    }

    /// Only channels the guide actually covers — a row of blanks helps nobody.
    private var channels: [MediaItem] {
        guard let guide = model.guide else { return [] }
        return model.library.channels.filter { channel in
            guard let id = channel.channelID else { return false }
            return guide.schedules[id]?.programmes.isEmpty == false
        }
    }

    private func programmes(for channel: MediaItem) -> [Programme] {
        guard let id = channel.channelID, let schedule = model.guide?.schedules[id] else {
            return []
        }
        let end = timelineStart.addingTimeInterval((hoursBefore + hoursAfter) * 3600)
        return schedule.programmes.filter { $0.stop > timelineStart && $0.start < end }
    }

    private func channel(for programme: Programme) -> MediaItem? {
        model.library.channels.first { $0.channelID == programme.channelID }
    }

    #if os(tvOS)
    private var hourWidth: CGFloat { 420 }
    private var rowHeight: CGFloat { 84 }
    private var channelColumnWidth: CGFloat { 260 }
    private var headerHeight: CGFloat { 44 }
    #else
    private var hourWidth: CGFloat { 240 }
    private var rowHeight: CGFloat { 62 }
    private var channelColumnWidth: CGFloat { 132 }
    private var headerHeight: CGFloat { 28 }
    #endif
    private var rowSpacing: CGFloat { 2 }
}

/// One channel's strip of programmes, laid out by time rather than by order.
struct GuideRow: View {
    let programmes: [Programme]
    let timelineStart: Date
    let hourWidth: CGFloat
    let rowHeight: CGFloat
    let now: Date
    let onSelect: (Programme) -> Void
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(programmes) { programme in
                Button {
                    // What is on now is a thing you watch; what is on later is
                    // a thing you read about.
                    if programme.isOnAir(at: now) { onPlay() } else { onSelect(programme) }
                } label: {
                    GuideBlock(programme: programme, now: now)
                        .frame(width: width(of: programme), height: rowHeight)
                }
                .buttonStyle(KanalCardButtonStyle())
                .offset(x: x(of: programme))
            }
        }
    }

    private func x(of programme: Programme) -> CGFloat {
        max(CGFloat(programme.start.timeIntervalSince(timelineStart) / 3600) * hourWidth, 0)
    }

    private func width(of programme: Programme) -> CGFloat {
        // Clipped to the visible timeline, and never so narrow it cannot be hit.
        let start = max(programme.start, timelineStart)
        let hours = programme.stop.timeIntervalSince(start) / 3600
        return max(CGFloat(hours) * hourWidth - 2, 24)
    }
}

struct GuideBlock: View {
    let programme: Programme
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(programme.title)
                .font(KanalFont.body(12))
                .foregroundStyle(KanalColor.primaryText)
                .lineLimit(1)
            Text(programme.start.formatted(date: .omitted, time: .shortened))
                .font(KanalFont.caption(10))
                .foregroundStyle(KanalColor.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KanalMetrics.sm)
        .padding(.vertical, KanalMetrics.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isOnAir ? KanalColor.surfaceElevated : KanalColor.surface)
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if isOnAir {
                Rectangle()
                    .fill(KanalColor.accent)
                    .frame(height: 2)
                    .scaleEffect(x: programme.progress(at: now), anchor: .leading)
            }
        }
    }

    private var isOnAir: Bool { programme.isOnAir(at: now) }
}

/// Details for something not on yet.
struct ProgrammeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let programme: Programme
    let channel: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            if let channel {
                Text(channel.title)
                    .kanalLabel(12)
                    .foregroundStyle(KanalColor.accentSolid)
            }
            Text(programme.title)
                .kanalDisplay(26)
                .foregroundStyle(KanalColor.primaryText)
            if let subtitle = programme.subtitle {
                Text(subtitle)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
            }

            HStack(spacing: KanalMetrics.sm) {
                MetaChip(timeRange)
                if let code = programme.episodeCode { MetaChip(code) }
                ForEach(programme.categories.prefix(2), id: \.self) { category in
                    MetaChip(CategoryLocalizer.display(category))
                }
            }

            if let description = programme.description {
                ScrollView {
                    Text(description)
                        .font(KanalFont.body(14))
                        .foregroundStyle(KanalColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(KanalMetrics.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KanalColor.background)
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationBackground(KanalColor.background)
        #endif
    }

    private var timeRange: String {
        let start = programme.start.formatted(date: .omitted, time: .shortened)
        let stop = programme.stop.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(stop)"
    }
}
