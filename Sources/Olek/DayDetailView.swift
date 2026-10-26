import SwiftUI
import OlekCore

struct DayDetailView: View {
    let date: LocalDate
    let model: TrackingController
    let ledger: Ledger
    let today: LocalDate
    @Binding var selected: LocalDate

    @State private var editor: SessionEditor.Mode?
    @State private var breakSession: Session?
    @State private var pendingDelete: Session?

    var body: some View {
        let plan = ledger.plan(for: date)
        let summary = PeriodSummary(worked: ledger.worked(on: date), expected: plan.expected)
        let sessions = model.sessions(on: date)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { selected = date.adding(days: -1) } label: {
                        Label("Previous Day", systemImage: "chevron.left").labelStyle(.iconOnly)
                    }
                    .help("Previous day")
                    Text(DateFormat.long(date))
                        .font(.title2.weight(.semibold))
                    Button { selected = date.adding(days: 1) } label: {
                        Label("Next Day", systemImage: "chevron.right").labelStyle(.iconOnly)
                    }
                    .help("Next day")
                }
                .buttonStyle(.borderless)

                SummaryGrid(summary: summary, differenceLabel: "Difference", difference: summary.difference)

                DayTypeEditor(date: date, plan: plan, model: model, ledger: ledger)

                Divider()

                HStack {
                    Text("Sessions").font(.headline)
                    Spacer()
                    Button {
                        editor = .add(date)
                    } label: {
                        Label("Add Session", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(date > today)
                }

                if sessions.isEmpty {
                    Text(date > today ? "This day is in the future." : "No sessions recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sessions) { session in
                            SessionRow(
                                session: session,
                                date: date,
                                now: model.now,
                                onEdit: { editor = .edit(session) },
                                onBreak: { breakSession = session },
                                onDelete: { pendingDelete = session }
                            )
                            if session.id != sessions.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editor) { mode in
            SessionEditor(mode: mode, model: model, today: today)
        }
        .sheet(item: $breakSession) { session in
            BreakEditor(session: session, model: model)
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { session in
            Button("Delete", role: .destructive) { model.deleteSession(session) }
        } message: { session in
            Text("\(SessionRow.rangeText(session, on: date)) will be removed. This cannot be undone.")
        }
    }
}

struct SummaryGrid: View {
    let summary: PeriodSummary
    let differenceLabel: LocalizedStringKey
    /// Shown in the last column. Periods pass their through-yesterday balance; `nil` shows a dash.
    let difference: TimeInterval?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 4) {
            GridRow {
                Text("Worked")
                Text("Expected")
                Text("Completion")
                Text(differenceLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            GridRow {
                Text(DurationFormat.hoursMinutes(summary.worked))
                Text(DurationFormat.hoursMinutes(summary.expected))
                Text(summary.completion.map(PercentFormat.whole) ?? String(localized: "No scheduled hours"))
                Text(difference.map(DurationFormat.signed) ?? "\u{2013}")
                    .foregroundStyle((difference ?? 0) < -59 ? .orange : .primary)
            }
            .font(.title3.monospacedDigit())
        }
    }
}

// MARK: - Day type

private struct DayTypeEditor: View {
    let date: LocalDate
    let plan: DayPlan
    let model: TrackingController
    let ledger: Ledger

    @State private var note = ""

    private var override: DayOverride? { model.dayOverride(on: date) }
    private var basePlan: DayPlan { ledger.workingCalendar.basePlan(for: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Day type", selection: kindBinding) {
                    Text("Normal").tag(DayOverride.Kind?.none)
                    Divider()
                    Text("Vacation").tag(DayOverride.Kind?.some(.vacation))
                    Text("Day off").tag(DayOverride.Kind?.some(.dayOff))
                    Text("Sick leave").tag(DayOverride.Kind?.some(.sick))
                    Text("Non-working day").tag(DayOverride.Kind?.some(.customNonWorking))
                    Divider()
                    Text("Working day").tag(DayOverride.Kind?.some(.customWorking))
                    Text("Adjusted hours").tag(DayOverride.Kind?.some(.minutes))
                }
                .fixedSize()
                .accessibilityLabel("Day type")

                if let override, override.kind == .customWorking || override.kind == .minutes {
                    Stepper(value: minutesBinding(override), in: 0...(24 * 60), step: 15) {
                        Text("\(DurationFormat.hoursMinutes(TimeInterval((override.expectedMinutes ?? 0) * 60))) expected")
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }

            if override == nil {
                Text(DayDescription.text(for: plan))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("Note", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveNote)
                        .frame(maxWidth: 280)
                    Text("Normally: \(DayDescription.text(for: basePlan)), \(DurationFormat.hoursMinutes(basePlan.expected))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { note = override?.note ?? "" }
        .onChange(of: date) { note = override?.note ?? "" }
    }

    private var kindBinding: Binding<DayOverride.Kind?> {
        Binding(
            get: { override?.kind },
            set: { kind in
                guard let kind else {
                    model.removeDayOverride(on: date)
                    return
                }
                var minutes: Int?
                if kind == .customWorking || kind == .minutes {
                    let normal = basePlan.expectedMinutes
                    minutes = override?.expectedMinutes ?? (normal > 0 ? normal : WorkSettings.standardWeek[0])
                }
                model.setDayOverride(DayOverride(date: date, kind: kind, expectedMinutes: minutes, note: override?.note))
            }
        )
    }

    private func minutesBinding(_ override: DayOverride) -> Binding<Int> {
        Binding(
            get: { override.expectedMinutes ?? 0 },
            set: { minutes in
                var updated = override
                updated.expectedMinutes = minutes
                model.setDayOverride(updated)
            }
        )
    }

    private func saveNote() {
        guard var updated = override else { return }
        updated.note = note.isEmpty ? nil : note
        model.setDayOverride(updated)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: Session
    let date: LocalDate
    let now: Date
    let onEdit: () -> Void
    let onBreak: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(Self.rangeText(session, on: date))
                    .monospacedDigit()
                if session.isOpen {
                    Text("running")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.green.opacity(0.2)))
                }
                Spacer()
                Text(DurationFormat.hoursMinutes((session.end ?? now).timeIntervalSince(session.start)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(action: onEdit) { Label("Edit Session", systemImage: "pencil").labelStyle(.iconOnly) }
                    .help("Edit times")
                Button(action: onBreak) { Label("Add Break", systemImage: "scissors").labelStyle(.iconOnly) }
                    .help("Add a break inside this session")
                Button(action: onDelete) { Label("Delete Session", systemImage: "trash").labelStyle(.iconOnly) }
                    .help("Delete session")
            }
            .buttonStyle(.borderless)
            if let note = session.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    /// "09:00 – 17:00", with the weekday added for ends that fall on another date.
    static func rangeText(_ session: Session, on date: LocalDate) -> String {
        let calendar = Calendar.autoupdatingCurrent
        func label(_ time: Date) -> String {
            let day = LocalDate(time, calendar: calendar)
            let clock = TimeFormat.hourMinute(time)
            return day == date ? clock : "\(DateFormat.weekdayDayMonth(day)) \(clock)"
        }
        let end = session.end.map(label) ?? String(localized: "now")
        return "\(label(session.start)) \u{2013} \(end)"
    }
}
