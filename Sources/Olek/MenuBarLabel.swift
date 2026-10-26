import SwiftUI
import OlekCore

struct MenuBarLabel: View {
    let model: TrackingController

    var body: some View {
        if let duration = model.sessionDuration(at: model.now) {
            Text("\(Image(systemName: symbol)) \(DurationFormat.hoursMinutes(duration))")
        } else {
            Image(systemName: symbol)
        }
    }

    private var symbol: String {
        if model.notice != nil { return "clock.badge.exclamationmark" }
        return model.isWorking ? "stopwatch.fill" : "stopwatch"
    }
}
