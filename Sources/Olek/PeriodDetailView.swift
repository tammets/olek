import SwiftUI
import OlekCore

/// Week, month, or year around the selected date: totals plus one row per day or month.
struct PeriodDetailView: View {
    let scope: HistoryScope
    let anchor: LocalDate
    let ledger: Ledger
    let today: LocalDate
    @Binding var selected: LocalDate
    @Binding var currentScope: HistoryScope

    @State private var tableSelection: LocalDate?

    struct Row: Identifiable {
        let id: LocalDate
        let label: String
        let worked: TimeInterval
        let expected: TimeInterval
        let difference: TimeInterval?
        let status: DayStatus?
    }

    var body: some View {
        let (first, last) = bounds
        let progress = PeriodProgress(first: first, last: last, today: today, ledger: ledger)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { selected = step(-1) } label: {
                    Label("Previous", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .help("Previous")
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.title2.weight(.semibold))
                    if scope == .week {
                        Text(DateFormat.range(first, last)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button { selected = step(1) } label: {
                    Label("Next", systemImage: "chevron.right").labelStyle(.iconOnly)
                }
                .help("Next")
            }
            .buttonStyle(.borderless)

            SummaryGrid(
                summary: progress.whole,
                differenceLabel: "Balance",
                difference: hasAccountedPast(first: first, last: last) ? progress.toDate.difference : nil
            )
            Text(balanceNote(first: first, last: last))
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(rows(first: first, last: last), selection: $tableSelection) {
                TableColumn(scope == .year ? "Month" : "Day") { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(row.status.map(StatusStyle.color) ?? .clear)
                            .frame(width: 7, height: 7)
                        Text(row.label)
                    }
                }
                .width(min: 90, ideal: 110)
                TableColumn("Worked") { row in
                    Text(row.worked >= 60 ? DurationFormat.hoursMinutes(row.worked) : "\u{2013}").monospacedDigit()
                }
                .width(min: 60, ideal: 72)
                TableColumn("Expected") { row in
                    Text(row.expected > 0 ? DurationFormat.hoursMinutes(row.expected) : "\u{2013}").monospacedDigit()
                }
                .width(min: 60, ideal: 72)
                TableColumn("Difference") { row in
                    if let difference = row.difference {
                        Text(DurationFormat.signed(difference))
                            .monospacedDigit()
                            .foregroundStyle(difference < -59 ? .orange : .primary)
                    }
                }
                .width(min: 70, ideal: 80)
            }
            .contextMenu(forSelectionType: LocalDate.self) { _ in
            } primaryAction: { dates in
                // Double-click drills down: a month opens as a month, a day opens as a day.
                guard let date = dates.first else { return }
                selected = date
                currentScope = scope == .year ? .month : .day
            }
        }
    }

    private var bounds: (LocalDate, LocalDate) {
        switch scope {
        case .week: (anchor.startOfWeek, anchor.startOfWeek.adding(days: 6))
        case .year: (anchor.startOfYear, anchor.endOfYear)
        default: (anchor.startOfMonth, anchor.endOfMonth)
        }
    }

    private var title: String {
        switch scope {
        case .week: String(localized: "Week \(anchor.isoWeek)")
        case .year: String(anchor.year)
        default: DateFormat.monthYear(anchor)
        }
    }

    private func step(_ direction: Int) -> LocalDate {
        switch scope {
        case .week: anchor.adding(days: 7 * direction)
        case .year: LocalDate(year: anchor.year + direction, month: anchor.month, day: 1)
        default: direction < 0 ? anchor.startOfMonth.adding(days: -1).startOfMonth : anchor.endOfMonth.adding(days: 1)
        }
    }

    /// True when at least one finished, accounted day lies inside the period.
    private func hasAccountedPast(first: LocalDate, last: LocalDate) -> Bool {
        max(first, ledger.workingCalendar.accountingStart) <= min(last, today.adding(days: -1))
    }

    private func balanceNote(first: LocalDate, last: LocalDate) -> String {
        if today > last { return String(localized: "Balance covers the whole period.") }
        if today < first { return String(localized: "This period has not started yet.") }
        return String(localized: "Balance runs through yesterday; completion includes today.")
    }

    private func rows(first: LocalDate, last: LocalDate) -> [Row] {
        if scope == .year {
            return (1...12).map { month in
                let start = LocalDate(year: anchor.year, month: month, day: 1)
                let progress = PeriodProgress(first: start, last: start.endOfMonth, today: today, ledger: ledger)
                return Row(
                    id: start,
                    label: DateFormat.month(start),
                    worked: progress.whole.worked,
                    expected: progress.whole.expected,
                    difference: hasAccountedPast(first: start, last: start.endOfMonth) ? progress.toDate.difference : nil,
                    status: nil
                )
            }
        }
        return first.through(last).map { date in
            let plan = ledger.plan(for: date)
            let worked = ledger.worked(on: date)
            let counted = plan.reason != .beforeAccounting && date < today
            return Row(
                id: date,
                label: DateFormat.weekdayDayMonth(date),
                worked: worked,
                expected: plan.expected,
                difference: counted ? worked - plan.expected : nil,
                status: ledger.status(on: date, today: today)
            )
        }
    }
}
