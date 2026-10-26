import SwiftUI
import OlekCore

enum HistoryScope: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
}

struct HistoryView: View {
    let model: TrackingController

    @State private var selected = LocalDate(Date(), calendar: .autoupdatingCurrent)
    @State private var visibleMonth = LocalDate(Date(), calendar: .autoupdatingCurrent).startOfMonth
    @State private var scope: HistoryScope = .day
    @FocusState private var calendarFocused: Bool

    var body: some View {
        Group {
            if let ledger = model.ledger, let overview = model.overview {
                HSplitView {
                    sidebar(ledger: ledger, overview: overview)
                        .frame(minWidth: 400, idealWidth: 430, maxWidth: 520)
                    detail(ledger: ledger, today: overview.today)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Text(model.errorMessage ?? String(localized: "Loading…"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        // English UI with European conventions: 24-hour clock, day before month.
        .environment(\.locale, Locale(identifier: "en_GB"))
        .onChange(of: selected) { _, date in
            if date.startOfMonth != visibleMonth { visibleMonth = date.startOfMonth }
        }
        .regularAppWhileVisible()
        .onAppear { calendarFocused = true }
    }

    // MARK: Sidebar

    private func sidebar(ledger: Ledger, overview: Overview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { visibleMonth = visibleMonth.adding(days: -1).startOfMonth } label: {
                    Label("Previous Month", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Previous month")

                Text(DateFormat.monthYear(visibleMonth))
                    .font(.title2.weight(.semibold))
                    .frame(minWidth: 170)

                Button { visibleMonth = visibleMonth.endOfMonth.adding(days: 1) } label: {
                    Label("Next Month", systemImage: "chevron.right").labelStyle(.iconOnly)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Next month")

                Spacer()

                Button("Today") {
                    selected = overview.today
                    visibleMonth = overview.today.startOfMonth
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            .buttonStyle(.borderless)

            CalendarGrid(month: visibleMonth, selected: $selected, ledger: ledger, today: overview.today)
                .focusable()
                .focused($calendarFocused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { move(-1) }
                .onKeyPress(.rightArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-7) }
                .onKeyPress(.downArrow) { move(7) }
                .onKeyPress(.return) { scope = .day; return .handled }

            StatusLegend()

            Divider()

            BalancePanel(overview: overview)

            Spacer()
        }
        .padding(20)
    }

    private func move(_ days: Int) -> KeyPress.Result {
        selected = selected.adding(days: days)
        return .handled
    }

    // MARK: Detail

    private func detail(ledger: Ledger, today: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("View", selection: $scope) {
                ForEach(HistoryScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            switch scope {
            case .day:
                DayDetailView(date: selected, model: model, ledger: ledger, today: today, selected: $selected)
            case .week, .month, .year:
                PeriodDetailView(scope: scope, anchor: selected, ledger: ledger, today: today, selected: $selected, currentScope: $scope)
            }
        }
        .padding(20)
    }
}

// MARK: - Calendar grid

private struct CalendarGrid: View {
    let month: LocalDate
    @Binding var selected: LocalDate
    let ledger: Ledger
    let today: LocalDate

    private static let weekdayInitials = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    var body: some View {
        let first = month.startOfMonth.startOfWeek
        let last = month.endOfMonth.startOfWeek.adding(days: 6)
        let days = first.through(last)
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< $0 + 7]) }

        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("Wk").gridColumnAlignment(.trailing)
                ForEach(Self.weekdayInitials, id: \.self) { Text($0) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(weeks, id: \.first) { week in
                GridRow {
                    Text("\(week[0].isoWeek)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 7)
                    ForEach(week, id: \.self) { date in
                        Button { selected = date } label: {
                            DayCell(
                                date: date,
                                plan: ledger.plan(for: date),
                                worked: ledger.worked(on: date),
                                status: ledger.status(on: date, today: today),
                                isSelected: date == selected,
                                isToday: date == today,
                                inMonth: date.month == month.month
                            )
                        }
                        .buttonStyle(.plain)
                        // Arrow keys on the grid move the selection; cells need not take focus one by one.
                        .focusable(false)
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: LocalDate
    let plan: DayPlan
    let worked: TimeInterval
    let status: DayStatus
    let isSelected: Bool
    let isToday: Bool
    let inMonth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text("\(date.day)")
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(status == .beforeAccounting ? .secondary : .primary)
                Spacer(minLength: 0)
                if case .holiday = plan.reason {
                    Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(.secondary)
                } else if case .override = plan.reason {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(worked >= 60 ? DurationFormat.hoursMinutes(worked) : " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(5)
        .frame(minWidth: 46, maxWidth: .infinity, minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 6).fill(StatusStyle.color(status).opacity(0.22)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : (isToday ? Color.secondary : .clear), lineWidth: isSelected ? 2 : 1)
        )
        .opacity(inMonth ? 1 : 0.4)
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(DateFormat.long(date)), \(tooltip)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tooltip: String {
        let description = DayDescription.text(for: plan)
        guard plan.expectedMinutes > 0 || worked > 0 else { return description }
        return String(localized: "\(description) · \(DurationFormat.hoursMinutes(worked)) of \(DurationFormat.hoursMinutes(plan.expected))")
    }
}

enum StatusStyle {
    static func color(_ status: DayStatus) -> Color {
        switch status {
        case .met: .green
        case .below: .orange
        case .noRecord: .red
        case .nonWorking: .gray
        case .inProgress: .blue
        case .future, .beforeAccounting: .clear
        }
    }
}

private struct StatusLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            item(.met, "Target met")
            item(.below, "Below target")
            item(.noRecord, "No record")
            item(.nonWorking, "Day off")
            item(.inProgress, "Today")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func item(_ status: DayStatus, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(StatusStyle.color(status).opacity(0.5))
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

private struct BalancePanel: View {
    let overview: Overview

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Balance").font(.headline)
                Text(DurationFormat.signed(overview.balance))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(overview.balance < -59 ? .orange : .primary)
                    .gridColumnAlignment(.trailing)
            }
            GridRow {
                Text("Including today").foregroundStyle(.secondary)
                Text(DurationFormat.signed(overview.balanceIncludingToday)).monospacedDigit().foregroundStyle(.secondary)
            }
            GridRow {
                Text("This year").foregroundStyle(.secondary)
                Text(DurationFormat.signed(overview.year.toDate.difference)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        Text("Through yesterday, since \(DateFormat.dayMonthYear(overview.accountingStart))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
