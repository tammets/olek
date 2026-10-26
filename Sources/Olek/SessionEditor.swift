import SwiftUI
import OlekCore

private func minuteFloor(_ date: Date) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
}

struct SessionEditor: View {
    enum Mode: Identifiable {
        case add(LocalDate)
        case edit(Session)

        var id: String {
            switch self {
            case .add(let date): "add-\(date)"
            case .edit(let session): "edit-\(session.id)"
            }
        }
    }

    let mode: Mode
    let model: TrackingController

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var running: Bool
    @State private var note: String
    @State private var error: String?

    init(mode: Mode, model: TrackingController, today: LocalDate) {
        self.mode = mode
        self.model = model
        switch mode {
        case .add(let date):
            // Default to a 09:00-17:00 day, cut short at the current time when adding to today.
            let dayStart = date.interval(in: .autoupdatingCurrent).start
            let now = minuteFloor(Date())
            var end = dayStart.addingTimeInterval(17 * 3600)
            var start = dayStart.addingTimeInterval(9 * 3600)
            if date == today {
                end = min(end, now)
                start = min(start, end.addingTimeInterval(-3600))
            }
            _start = State(initialValue: start)
            _end = State(initialValue: end)
            _running = State(initialValue: false)
            _note = State(initialValue: "")
        case .edit(let session):
            _start = State(initialValue: session.start)
            _end = State(initialValue: session.end ?? minuteFloor(Date()))
            _running = State(initialValue: session.isOpen)
            _note = State(initialValue: session.note ?? "")
        }
    }

    private var isEditingOpenSession: Bool {
        if case .edit(let session) = mode { return session.isOpen }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isAdding ? "Add Session" : "Edit Session")
                .font(.headline)

            Form {
                DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                if isEditingOpenSession {
                    Toggle("Still running", isOn: $running)
                }
                if !running {
                    DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Note", text: $note)
                LabeledContent("Duration") {
                    Text(durationText).monospacedDigit()
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!running && end <= start)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var durationText: String {
        let finish = running ? Date() : end
        guard finish > start else { return "\u{2013}" }
        return DurationFormat.hoursMinutes(finish.timeIntervalSince(start))
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .add:
                try model.addSession(start: minuteFloor(start), end: minuteFloor(end), note: trimmedNote.isEmpty ? nil : trimmedNote)
            case .edit(var session):
                // Times the user touched snap to whole minutes; untouched ones keep their seconds.
                if start != session.start { session.start = minuteFloor(start) }
                if running {
                    session.end = nil
                } else if end != session.end {
                    session.end = minuteFloor(end)
                }
                session.note = trimmedNote.isEmpty ? nil : trimmedNote
                try model.saveSession(session)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BreakEditor: View {
    let session: Session
    let model: TrackingController

    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date
    @State private var error: String?

    init(session: Session, model: TrackingController) {
        self.session = session
        self.model = model
        let end = session.end ?? Date()
        let middle = minuteFloor(session.start.addingTimeInterval(end.timeIntervalSince(session.start) / 2))
        _from = State(initialValue: middle)
        _to = State(initialValue: min(middle.addingTimeInterval(30 * 60), minuteFloor(end.addingTimeInterval(-60))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Break").font(.headline)
            Text("The session is split in two, leaving out the break.")
                .foregroundStyle(.secondary)

            Form {
                DatePicker("Break from", selection: $from, displayedComponents: components)
                DatePicker("Break until", selection: $to, displayedComponents: components)
                LabeledContent("Break length") {
                    Text(to > from ? DurationFormat.hoursMinutes(to.timeIntervalSince(from)) : "\u{2013}")
                        .monospacedDigit()
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Break", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(to <= from)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// The date is only needed when the session crosses midnight.
    private var components: DatePickerComponents {
        let calendar = Calendar.autoupdatingCurrent
        let end = session.end ?? Date()
        return calendar.isDate(session.start, inSameDayAs: end) ? [.hourAndMinute] : [.date, .hourAndMinute]
    }

    private func save() {
        do {
            try model.insertBreak(in: session, from: minuteFloor(from), to: minuteFloor(to))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
