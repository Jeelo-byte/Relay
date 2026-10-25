import RelayKit
import SwiftUI
import UserNotifications

@MainActor final class ReminderScheduler: ObservableObject {
  @Published var status = ""
  // UserNotifications raises an Objective-C exception for a bare SwiftPM
  // executable. Only initialize it when running inside an application bundle.
  private let center: UNUserNotificationCenter? = {
    guard Bundle.main.bundleURL.pathExtension == "app",
      Bundle.main.bundleIdentifier != nil else { return nil }
    return UNUserNotificationCenter.current()
  }()
  private let unavailableMessage = "Reminders require the Relay app bundle. Open Relay.app or run the Relay app scheme in Xcode."
  private var generation = 0
  private var work: Task<Void, Never>?

  func enable(agreements: [Agreement]) async -> Bool {
    guard let center else { status = unavailableMessage; return false }
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      guard granted else { status = "Notifications are disabled in system settings."; return false }
      UserDefaults.standard.set(true, forKey: "relay.reminders")
      await refresh(agreements: agreements)
      return true
    } catch { status = error.localizedDescription; return false }
  }
  func refresh(agreements: [Agreement]) async {
    generation += 1
    let current = generation
    let previous = work
    let next = Task { @MainActor in
      await previous?.value
      guard current == self.generation else { return }
      await self.schedule(agreements: agreements, current: current)
    }
    work = next
    await next.value
  }
  private func schedule(agreements: [Agreement], current: Int) async {
    guard let center else { status = unavailableMessage; return }
    let pending = await center.pendingNotificationRequests()
    guard current == generation else { return }
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("relay.due.") }.map(\.identifier))
    guard UserDefaults.standard.bool(forKey: "relay.reminders") else { status = "Reminders are off."; return }
    let settings = await center.notificationSettings()
    guard current == generation else { return }
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      status = "Enable notifications for Relay in system settings."; return
    }
    let plan = ReminderPlan.make(agreements: agreements)
    do {
      for reminder in plan {
        guard current == generation else { return }
        let content = UNMutableNotificationContent()
        content.title = "Relay reminder"
        content.body = "An agreement is coming due. Open Relay to review it."
        content.sound = .default
        let interval = reminder.fireDate.timeIntervalSinceNow
        guard interval > 0 else { continue }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
      }
      if current == generation { status = "\(plan.count) upcoming reminders scheduled." }
    } catch { status = "Reminders could not be scheduled: \(error.localizedDescription)" }
  }
  func disable() async {
    UserDefaults.standard.set(false, forKey: "relay.reminders")
    await refresh(agreements: [])
  }
}
