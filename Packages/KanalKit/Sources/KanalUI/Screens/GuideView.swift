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
    @State private var selectedChannel: ChannelGroup?
    @State private var now = Date.now
    @State private var returnToNowRequest = 0
    #if os(tvOS)
    @State private var focusedProgramme: Programme?
    @State private var focusedChannel: ChannelGroup?
    #endif

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
            ProgrammeSheet(programme: programme, channel: selectedChannel ?? channel(for: programme))
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
        #if os(tvOS)
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            selectedProgrammePanel
            guideScrollView
        }
        .padding(.horizontal, KanalMetrics.lg)
        .padding(.top, KanalMetrics.md)
        #else
        guideScrollView
        #endif
    }

    private var guideScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    rows
                        .padding(.leading, channelColumnWidth)
                        .padding(.top, headerHeight)

                    nowLine
                        .padding(.leading, channelColumnWidth)
                        .padding(.top, headerHeight)

                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(x: channelColumnWidth + xPosition(for: now), y: headerHeight)
                        .id("guide-now")

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
            #if os(tvOS)
            .onAppear {
                // The timeline is generated around now; make that useful
                // immediately even when tvOS restores an old scroll position.
                proxy.scrollTo("guide-now", anchor: .center)
            }
            .onChange(of: returnToNowRequest) { _, _ in
                proxy.scrollTo("guide-now", anchor: .center)
            }
            #endif
        }
    }

    #if os(tvOS)
    private var selectedProgrammePanel: some View {
        HStack(alignment: .top, spacing: KanalMetrics.lg) {
            VStack(alignment: .leading, spacing: KanalMetrics.xs) {
                if let focusedProgramme {
                    Text(focusedProgramme.title)
                        .kanalDisplay(32)
                        .foregroundStyle(KanalColor.primaryText)
                        .lineLimit(2)
                    Text(focusedChannel?.name ?? channel(for: focusedProgramme)?.name ?? "")
                        .kanalLabel(26)
                        .foregroundStyle(KanalColor.accentSolid)
                    Text(timeRange(for: focusedProgramme))
                        .font(KanalFont.caption(22))
                        .foregroundStyle(KanalColor.secondaryText)
                    if let description = focusedProgramme.description, !description.isEmpty {
                        Text(description)
                            .font(KanalFont.body(22))
                            .foregroundStyle(KanalColor.secondaryText)
                            .lineLimit(2)
                    }
                } else {
                    Text(String(UIStrings.guide))
                        .kanalDisplay(32)
                        .foregroundStyle(KanalColor.primaryText)
                }
            }
            Spacer(minLength: KanalMetrics.md)
            Button {
                // Resetting the anchor is enough to bring the now line back
                // into view; the next geometry callback updates pinned axes.
                returnToNowRequest += 1
                selected = nil
                focusedProgramme = nil
                focusedChannel = nil
            } label: {
                Label(String(UIStrings.guideReturnToNow), systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(KanalCardButtonStyle())
            .accessibilityLabel(Text(UIStrings.guideReturnToNow))
        }
        .frame(height: 220, alignment: .topLeading)
    }

    private func timeRange(for programme: Programme) -> String {
        let start = programme.start.formatted(date: .omitted, time: .shortened)
        let stop = programme.stop.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(stop)"
    }
    #endif

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(channels) { channel in
                GuideRow(
                    programmes: programmes(for: channel),
                    timelineStart: timelineStart,
                    hourWidth: hourWidth,
                    rowHeight: rowHeight,
                    now: now,
                    onSelect: { selected = $0; selectedChannel = channel },
                    onFocus: { programme in
                        #if os(tvOS)
                        focusedProgramme = programme
                        focusedChannel = channel
                        #endif
                    },
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
                            url: channel.logoURL, title: channel.name,
                            symbol: "tv", contentMode: .fit
                        )
                        .frame(width: rowHeight * 0.7, height: rowHeight * 0.7)
                        .background(KanalColor.surface)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))

                        Text(channel.name)
                            .font(KanalFont.body(26))
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
                    .font(KanalFont.caption(22))
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
    private var channels: [ChannelGroup] {
        guard let guide = model.guide else { return [] }
        return model.library.channelGroups.filter { group in
            group.variants.contains { variant in
                guard let id = variant.channelID else { return false }
                return guide.schedules[id]?.programmes.isEmpty == false
            }
        }
    }

    private func programmes(for channel: ChannelGroup) -> [Programme] {
        guard let guide = model.guide else { return [] }
        let end = timelineStart.addingTimeInterval((hoursBefore + hoursAfter) * 3600)
        var merged: [Programme] = []
        var seen = Set<String>()
        for variant in channel.variants {
            guard let id = variant.channelID, let schedule = guide.schedules[id] else { continue }
            for programme in schedule.programmes where programme.stop > timelineStart && programme.start < end {
                // XMLTV variants may use different channel IDs for the same
                // feed. Start time is the stable identity for a guide slot.
                let key = "\(programme.start.timeIntervalSince1970)|\(programme.title)"
                if seen.insert(key).inserted { merged.append(programme) }
            }
        }
        return merged.sorted { $0.start < $1.start }
    }

    private func channel(for programme: Programme) -> ChannelGroup? {
        model.library.channelGroups.first { group in
            group.variants.contains { $0.channelID == programme.channelID }
        }
    }

    #if os(tvOS)
    private var hourWidth: CGFloat { 480 }
    private var rowHeight: CGFloat { 112 }
    private var channelColumnWidth: CGFloat { 340 }
    private var headerHeight: CGFloat { 56 }
    #else
    @ScaledMetric(relativeTo: .body) private var hourWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 62
    @ScaledMetric(relativeTo: .body) private var channelColumnWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 28
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
    var onFocus: (Programme) -> Void = { _ in }
    #if os(tvOS)
    @FocusState private var focusedProgrammeID: String?
    #endif
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
                #if os(tvOS)
                .focused($focusedProgrammeID, equals: programme.id)
                #endif
                .offset(x: x(of: programme))
            }
        }
        #if os(tvOS)
        .onChange(of: focusedProgrammeID) { _, id in
            guard let id, let programme = programmes.first(where: { $0.id == id }) else { return }
            onFocus(programme)
        }
        #endif
    }

    private func x(of programme: Programme) -> CGFloat {
        max(CGFloat(programme.start.timeIntervalSince(timelineStart) / 3600) * hourWidth, 0)
    }

    private func width(of programme: Programme) -> CGFloat {
        // Clip at the next slot as well as the programme stop. Provider data
        // occasionally overlaps; letting blocks share a row makes short slots
        // unreadable and causes focus to jump between overlapping hit targets.
        let start = max(programme.start, timelineStart)
        let index = programmes.firstIndex(where: { $0.id == programme.id }) ?? 0
        let nextStart = programmes.dropFirst(index + 1).first?.start
        let visibleStop = min(programme.stop, nextStart ?? programme.stop)
        let hours = visibleStop.timeIntervalSince(start) / 3600
        let naturalWidth = max(CGFloat(hours) * hourWidth - 2, 28)
        guard let nextStart else { return naturalWidth }
        // Never let the accessibility hit target cross into the next slot.
        let gapWidth = max(CGFloat(nextStart.timeIntervalSince(start) / 3600) * hourWidth - 2, 2)
        return min(naturalWidth, gapWidth)
    }
}

struct GuideBlock: View {
    let programme: Programme
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(programme.title)
                .font(KanalFont.body(22))
                .foregroundStyle(KanalColor.primaryText)
                .lineLimit(1)
            Text(programme.start.formatted(date: .omitted, time: .shortened))
                .font(KanalFont.caption(22))
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
    let channel: ChannelGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: KanalMetrics.md) {
            if let channel {
                Text(channel.name)
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
