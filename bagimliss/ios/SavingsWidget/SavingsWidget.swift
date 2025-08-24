import WidgetKit
import SwiftUI
import Intents

struct SavingsEntry: TimelineEntry {
    let date: Date
    let savingsText: String
    let configuration: ConfigurationIntent
}

struct SavingsProvider: IntentTimelineProvider {
    func placeholder(in context: Context) -> SavingsEntry {
        SavingsEntry(date: Date(), savingsText: "0,00 TL", configuration: ConfigurationIntent())
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SavingsEntry) -> ()) {
        let entry = SavingsEntry(date: Date(), savingsText: "0,00 TL", configuration: configuration)
        completion(entry)
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SavingsEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let savingsText = UserDefaults(suiteName: "group.com.tasdemir.habitfree")?.string(forKey: "savings_text") ?? "0,00 TL"
            let entry = SavingsEntry(date: entryDate, savingsText: savingsText, configuration: configuration)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SavingsWidgetEntryView : View {
    var entry: SavingsProvider.Entry

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.427, green: 0.365, blue: 0.965), // #6D5DF6
                    Color(red: 0.275, green: 0.761, blue: 0.796)  // #46C2CB
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 8) {
                // Icon
                Image(systemName: "banknote.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                
                // Title
                Text("Tasarruf")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                // Savings amount
                Text(entry.savingsText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding()
        }
        .cornerRadius(16)
    }
}

struct SavingsWidget: Widget {
    let kind: String = "SavingsWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: SavingsProvider()) { entry in
            SavingsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Habit Free Tasarruf")
        .description("Bağımlılığı bırakarak tasarruf ettiğiniz tutarı gösterir.")
        .supportedFamilies([.systemSmall])
    }
}

struct SavingsWidget_Previews: PreviewProvider {
    static var previews: some View {
        SavingsWidgetEntryView(entry: SavingsEntry(date: Date(), savingsText: "1,234.56 TL", configuration: ConfigurationIntent()))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
