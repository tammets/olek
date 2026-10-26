import SwiftUI
import OlekCore

struct PopoverView: View {
    let model: TrackingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = model.notice {
                NoticeView(notice: notice, model: model)
            }

            Button(action: model.toggle) {
                Label(
                    model.isWorking ? "Stop" : "Start",
                    systemImage: model.isWorking ? "stop.fill" : "play.fill"
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isWorking ? .red : .green)
            .keyboardShortcut(.defaultAction)

            SessionSection(model: model)

            // Errors come from Start/Stop or the adjust buttons, so they sit right below those.
            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let overview = model.overview {
                Divider()
                TodaySection(overview: overview)
                Divider()
                PeriodRow(title: "This week", progress: overview.week)
                PeriodRow(title: "This month", progress: overview.month)
                Divider()
                BalanceSection(overview: overview)
            }

            Divider()

            HStack {
                Button("History") {
                    openWindow(id: "history")
                    NSApp.activate()
                }
                .keyboardShortcut("y")
                Spacer()
                Button("Quit Olek") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}

// MARK: - Session

private struct SessionSection: View {
    let model: TrackingController

    var body: some View {
        if let session = model.adjustableSession {
            VStack(alignment: .leading, spacing: 6) {
                if session.isOpen {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(DurationFormat.clock(context.date.timeIntervalSince(session.start)))
                            .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                    }
                } else {
                    Text(lastSessionTitle(session))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                AdjustRow(label: "Started", time: session.start, edge: .start, model: model)
                if let end = session.end {
                    AdjustRow(label: "Stopped", time: end, edge: .end, model: model)
                }
            }
        } else {
            Text("Not working")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func lastSessionTitle(_ session: Session) -> String {
        let date = LocalDate(session.start, calendar: .autoupdatingCurrent)
        let duration = DurationFormat.hoursMinutes(session.end.map { $0.timeIntervalSince(session.start) } ?? 0)
        if date == model.overview?.today {
            return String(localized: "Last session today · \(duration)")
        }
        return String(localized: "Last session \(DateFormat.weekdayDayMonth(date)) · \(duration)")
    }
}

/// One timestamp with buttons that move exactly that timestamp, so "-10" next to
/// "Started" can only mean "started ten minutes earlier".
private struct AdjustRow: View {
    let label: LocalizedStringKey
    let time: Date
    let edge: SessionEdge
    let model: TrackingController

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(TimeFormat.hourMinute(time))
                .monospacedDigit()
            Spacer()
            ForEach([-30, -10, 10, 30], id: \.self) { minutes in
                Button(minutes < 0 ? "\u{2212}\(-minutes)" : "+\(minutes)") {
                    model.adjust(edge, minutes: minutes)
                }
                .controlSize(.small)
                .monospacedDigit()
                .help(helpText(minutes))
                .accessibilityLabel(helpText(minutes))
            }
        }
    }

    private func helpText(_ minutes: Int) -> String {
        let amount = abs(minutes)
        switch (edge, minutes < 0) {
        case (.start, true): return String(localized: "Started \(amount) minutes earlier")
        case (.start, false): return String(localized: "Started \(amount) minutes later")
        case (.end, true): return String(localized: "Stopped \(amount) minutes earlier")
        case (.end, false): return String(localized: "Stopped \(amount) minutes later")
        }
    }
}

// MARK: - Statistics

private struct TodaySection: View {
    let overview: Overview

    var body: some View {
        let plan = overview.todayPlan
        let summary = PeriodSummary(worked: overview.todayWorked, expected: plan.expected)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Spacer()
                if summary.expected > 0 {
                    Text("\(DurationFormat.hoursMinutes(summary.worked)) of \(DurationFormat.hoursMinutes(summary.expected))")
                        .monospacedDigit()
                } else {
                    Text(DurationFormat.hoursMinutes(summary.worked))
                        .monospacedDigit()
                }
            }
            if let completion = summary.completion {
                ProgressView(value: min(completion, 1))
                    .tint(completion >= 1 ? .green : .accentColor)
            }
            HStack {
                Text(DayDescription.text(for: plan))
                    .foregroundStyle(.secondary)
                Spacer()
                if let completion = summary.completion {
                    Text(PercentFormat.whole(completion))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
        }
    }
}

private struct PeriodRow: View {
    let title: LocalizedStringKey
    let progress: PeriodProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                ToDateLabel(summary: progress.toDate)
            }
            Text(wholeLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var wholeLine: String {
        let whole = progress.whole
        let worked = DurationFormat.hoursMinutes(whole.worked)
        guard let completion = whole.completion else {
            return String(localized: "\(worked) worked · no scheduled hours")
        }
        return String(localized: "\(worked) of \(DurationFormat.hoursMinutes(whole.expected)) · \(PercentFormat.whole(completion))")
    }
}

/// "+1h 10m ahead" or "−2h behind", measured through yesterday.
private struct ToDateLabel: View {
    let summary: PeriodSummary

    var body: some View {
        let difference = summary.difference
        Group {
            if summary.expected == 0 && summary.worked == 0 {
                Text("Starts today").foregroundStyle(.secondary)
            } else if abs(difference) < 60 {
                Text("On schedule").foregroundStyle(.secondary)
            } else if difference > 0 {
                Text("\(DurationFormat.signed(difference)) ahead").foregroundStyle(.green)
            } else {
                Text("\(DurationFormat.signed(difference)) behind").foregroundStyle(.orange)
            }
        }
        .monospacedDigit()
        .help("Compared with expected hours through yesterday")
    }
}

private struct BalanceSection: View {
    let overview: Overview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Balance").font(.headline)
                Spacer()
                Text(DurationFormat.signed(overview.balance))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(overview.balance < -59 ? .orange : .primary)
            }
            Text("Through yesterday, since \(DateFormat.dayMonthYear(overview.accountingStart))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum DayDescription {
    static func text(for plan: DayPlan) -> String {
        switch plan.reason {
        case .schedule:
            plan.expectedMinutes > 0
                ? String(localized: "Workday")
                : String(localized: "Not a scheduled workday")
        case .holiday(let holiday):
            String(localized: "Holiday: \(holiday.name)")
        case .shortened(let holiday):
            String(localized: "Shortened day before \(holiday.name)")
        case .override(let kind):
            switch kind {
            case .vacation: String(localized: "Vacation")
            case .dayOff: String(localized: "Day off")
            case .sick: String(localized: "Sick leave")
            case .customNonWorking: String(localized: "Non-working day")
            case .customWorking: String(localized: "Custom working day")
            case .minutes: String(localized: "Adjusted hours")
            }
        case .beforeAccounting:
            String(localized: "Before accounting start")
        }
    }
}

// MARK: - Recovery notice

private struct NoticeView: View {
    let notice: RecoveryNotice
    let model: TrackingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch notice {
            case let .askedAboutGap(_, from, to):
                Text("Your Mac was asleep or Olek was not running from \(TimeFormat.hourMinute(from)) to \(TimeFormat.hourMinute(to)). Were you working?")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Yes, keep it") { model.keepGap() }
                    Button("Stop at \(TimeFormat.hourMinute(from))") { model.stopAtGapStart() }
                }
            case let .autoStopped(_, stoppedAt, awayUntil):
                Text("Stopped tracking at \(TimeFormat.hourMinute(stoppedAt)) because your Mac was away for \(DurationFormat.hoursMinutes(awayUntil.timeIntervalSince(stoppedAt))).")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Undo, I kept working") { model.undoAutoStop() }
                    Button("OK") { model.dismissNotice() }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
