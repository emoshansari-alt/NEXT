import NextKit
import SwiftUI

/// Settings. Short, and every switch says plainly what it does.
struct SettingsView: View {

    @State var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    private static let hours = Array(0...23)

    var body: some View {
        NavigationStack {
            Form {
                if model.remindersBlockedBySystem, let notice = model.notice ?? blockedNotice {
                    Section {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-notice")
                    }
                }

                remindersSection
                dailySection
                intelligenceSection
                nextPlusSection
                aboutSection
            }
            // Native background, deliberately — see the note in EverythingView. Rows are still
            // the card stock, so the palette's contrast guarantees apply to what is rendered.
            .listRowBackgroundIsCard()
            // The notice sits in a Section *above* the toggle the user just flipped, so VoiceOver
            // has already passed it by the time it appears — and the toggle stays visually on
            // while the system quietly refuses. Without this, a refused permission is silent.
            .announcesFailure(model.notice)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings-close-button")
                }
            }
        }
        .task { await model.load() }
    }

    private var blockedNotice: String? {
        "Notifications are turned off for NEXT in the Settings app."
    }

    // MARK: Sections

    private var remindersSection: some View {
        Section {
            Toggle(
                "Deadline reminders",
                isOn: Binding(
                    get: { model.preferences.deadlineRemindersEnabled },
                    set: { on in Task { await model.setDeadlineReminders(on) } }
                )
            )
            .accessibilityIdentifier("settings-deadline-toggle")

            if model.preferences.deadlineRemindersEnabled {
                Picker(
                    "Remind me",
                    selection: Binding(
                        get: { model.preferences.deadlineLeadTime },
                        set: { value in Task { await model.setLeadTime(value) } }
                    )
                ) {
                    ForEach(ReminderPreferences.leadTimeChoices, id: \.self) { choice in
                        Text(leadTimeLabel(choice)).tag(choice)
                    }
                }
                .accessibilityIdentifier("settings-lead-time-picker")
            }
        } header: {
            Text("Deadlines")
                .foregroundStyle(NextPalette.inkSecondary)
        } footer: {
            Text("One reminder before something you gave a deadline to. Nothing else.")
                .foregroundStyle(NextPalette.inkSecondary)
        }
    }

    private var dailySection: some View {
        Section {
            Toggle(
                "Daily reminder",
                isOn: Binding(
                    get: { model.preferences.dailyReminderEnabled },
                    set: { on in Task { await model.setDailyReminder(on) } }
                )
            )
            .accessibilityIdentifier("settings-daily-toggle")

            if model.preferences.dailyReminderEnabled {
                Picker(
                    "At",
                    selection: Binding(
                        get: { model.preferences.dailyReminderHour },
                        set: { hour in Task { await model.setDailyReminderHour(hour) } }
                    )
                ) {
                    ForEach(Self.hours, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .accessibilityIdentifier("settings-daily-hour-picker")
            }
        } header: {
            Text("Daily")
                .foregroundStyle(NextPalette.inkSecondary)
        } footer: {
            // Says what it is rather than selling it.
            Text("Off unless you want it. It says how much is outstanding, once a day.")
                .foregroundStyle(NextPalette.inkSecondary)
        }
    }

    private var intelligenceSection: some View {
        Section {
            Toggle(
                "Allow cloud processing",
                isOn: Binding(
                    get: { model.cloudIntelligenceConsented },
                    set: { model.setCloudIntelligenceConsent($0) }
                )
            )
            .accessibilityIdentifier("settings-cloud-ai-toggle")
        } header: {
            Text("Intelligence")
                .foregroundStyle(NextPalette.inkSecondary)
        } footer: {
            // The whole truth, including the part that says this changes nothing today.
            Text(
                """
                NEXT currently reads your notes entirely on this device, and nothing you write \
                is sent anywhere. If cloud processing is ever added, this switch controls it, \
                and only the text for that one request would be sent — never your whole list.
                """
            )
            .foregroundStyle(NextPalette.inkSecondary)
        }
    }

    /// The way in to NEXT+, when there is one.
    ///
    /// Absent from a normal build, because NEXT+ unlocks nothing today and a row offering to sell
    /// it would be offering something that does not exist. The screen behind it is complete and
    /// tested — see `MonetisationAvailability`. Pushed rather than presented: a sheet raised from
    /// inside a sheet is the presentation bug `TESTING.md` records.
    @ViewBuilder
    private var nextPlusSection: some View {
        if MonetisationAvailability.isPaywallReachable {
            Section {
                NavigationLink {
                    PaywallView(model: PaywallViewModel())
                } label: {
                    Text("NEXT+")
                }
                .accessibilityIdentifier("settings-next-plus")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Your tasks", value: "Stored on this device")
            LabeledContent("Account", value: "None")
        } header: {
            Text("Privacy")
                .foregroundStyle(NextPalette.inkSecondary)
        } footer: {
            Text("NEXT has no account and collects nothing about you.")
                .foregroundStyle(NextPalette.inkSecondary)
        }
    }

    // MARK: Labels

    private func leadTimeLabel(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        switch hours {
        case ..<24: return hours == 1 ? "1 hour before" : "\(hours) hours before"
        case 24: return "1 day before"
        default: return "\(hours / 24) days before"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
