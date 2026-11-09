import ActivityKit
import WidgetKit
import SwiftUI

private let orange = Color(red: 1, green: 0.47, blue: 0.09)

@main
struct RunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .center, spacing: 12) {
                Image("ActivityPotato").resizable().scaledToFit().frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(context.state.paused ? "PAUSED" : context.state.phase.uppercased())
                        .font(.caption.weight(.bold)).foregroundStyle(orange)
                    if let round = context.state.roundNumber, let total = context.state.roundCount {
                        Text("ROUND \(round) OF \(total)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let next = context.state.nextPhase, !context.state.complete {
                        Text("Next: \(next)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RunCountdown(state: context.state)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
              }
              IntervalStrip(state: context.state)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.14, green: 0.11, blue: 0.1))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.paused ? "Paused" : context.state.phase, systemImage: "figure.run")
                        .font(.caption.bold()).foregroundStyle(orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunCountdown(state: context.state).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let round = context.state.roundNumber, let total = context.state.roundCount {
                                Text("Round \(round) of \(total)")
                            }
                            Spacer()
                            if let next = context.state.nextPhase, !context.state.complete {
                                Text("Next: \(next)")
                            }
                        }.font(.caption2).foregroundStyle(.secondary)
                        IntervalStrip(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run").foregroundStyle(orange)
            } compactTrailing: {
                RunCountdown(state: context.state).font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.run").foregroundStyle(orange)
            }
            .keylineTint(orange)
        }
    }
}

private struct IntervalStrip: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if let kinds = state.intervalKinds, let index = state.intervalIndex, !kinds.isEmpty {
            HStack(spacing: 3) {
                ForEach(kinds.indices, id: \.self) { i in
                    Capsule()
                        .fill(i < index || state.complete ? orange.opacity(0.65) : i == index ? orange : Color.white.opacity(0.22))
                        .frame(height: i == index && !state.complete ? 7 : 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Interval \(min(index + 1, kinds.count)) of \(kinds.count), \(state.phase)")
        }
    }
}

private struct RunCountdown: View {
    let state: RunActivityAttributes.ContentState
    var body: some View {
        if state.complete { Text("Done") }
        else if let start = state.endsAt, !state.paused, state.countUp {
            Text(timerInterval: start...start.addingTimeInterval(7 * 24 * 60 * 60), countsDown: false, showsHours: false)
        }
        else if let end = state.endsAt, !state.paused {
            Text(timerInterval: Date.now...max(Date.now, end), countsDown: true, showsHours: false)
        } else {
            Text(String(format: "%02d:%02d", state.remaining / 60, state.remaining % 60))
        }
    }
}
