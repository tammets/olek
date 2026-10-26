import SwiftUI
import OlekCore

struct PopoverView: View {
    let model: TrackingController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    if let session = model.openSession {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DurationFormat.clock(context.date.timeIntervalSince(session.start)))
                                .font(.system(size: 28, weight: .medium, design: .rounded).monospacedDigit())
                            Text("Started \(TimeFormat.hourMinute(session.start))")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not working")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    LabeledContent("Today") {
                        Text(DurationFormat.hoursMinutes(model.todayWorked(at: context.date)))
                            .monospacedDigit()
                    }
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit Olek") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

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
