import SwiftUI
import OlekCore

struct MenuBarLabel: View {
    let model: TrackingController

    var body: some View {
        // The menu bar drops images interpolated into Text, so icon and text stay separate views.
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let duration = model.sessionDuration(at: model.now) {
                Text(DurationFormat.hoursMinutes(duration))
                    .monospacedDigit()
            }
        }
    }

    private var symbol: String {
        if model.notice != nil || model.reminder != nil { return "clock.badge.exclamationmark" }
        return model.isWorking ? "stopwatch.fill" : "stopwatch"
    }
}
