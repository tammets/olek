import SwiftUI
import OlekCore

struct MenuBarLabel: View {
    let model: TrackingController

    var body: some View {
        // The menu bar drops images interpolated into Text, so icon and text stay separate views.
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let text {
                Text(text).monospacedDigit()
            }
        }
    }

    private var text: String? {
        switch model.generalSettings.menuBarText {
        case .sessionWhileWorking:
            model.sessionDuration(at: model.now).map(DurationFormat.hoursMinutes)
        case .todayTotal:
            model.overview.map { DurationFormat.hoursMinutes($0.todayWorked) }
        case .iconOnly:
            nil
        }
    }

    private var symbol: String {
        if model.notice != nil || model.reminder != nil { return "clock.badge.exclamationmark" }
        return model.isWorking ? "stopwatch.fill" : "stopwatch"
    }
}
