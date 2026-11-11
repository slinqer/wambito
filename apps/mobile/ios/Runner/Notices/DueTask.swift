import BackgroundTasks
import Foundation
import UserNotifications
import WambitoNative

/// "Hoy vence…" (spec section 7.2) as a background app refresh task, the iOS side of `DueWorker`
/// (NoticeWorkers.kt): aimed at the next 9:00 in the profile's zone, it asks the server for the
/// recurring payments still pending today and posts one notice naming them; none when there are
/// none. Then it puts tomorrow's run on the calendar, unless the switch is off or the person is
/// signed out (a 401). The system decides when it really runs: never before that 9:00, maybe later.
///
///  * Its requests carry `x-wambito-background: 1`, so they never count as activity on the server.
///  * One notice per local day: the day is recorded (`DueSettings.lastDayKey`).
///  * It reads the session from the Keychain and never writes it ([KeychainSession]).
enum DueTask {
  static let identifier = "wambito.notice.due"

  /// From `didFinishLaunching`, before the launch ends, as BGTaskScheduler requires.
  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      let work = Task {
        let done = await run()
        refresh.setTaskCompleted(success: done)
      }
      // Out of time: cancelling the work cancels the request on its way, which ends the run as a
      // failure (tomorrow's run is still scheduled).
      refresh.expirationHandler = { work.cancel() }
    }
  }

  /// The next run at 9:00 in [zone], in place of the one waiting.
  static func schedule(zone: TimeZone, now: Date = Date()) {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = NoticeTimes.nextNine(after: now, in: zone)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // Background refresh is off for the app, or too many requests: nothing to tell anyone.
      NSLog("Wambito: the due notice could not be scheduled: \(error.localizedDescription)")
    }
  }

  static func cancel() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }

  /// One run; false when the network or the server failed.
  static func run(
    defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current(),
    session: KeychainSession = KeychainSession()
  ) async -> Bool {
    var zone = NoticeTimes.zone(defaults.string(forKey: DueSettings.zoneKey), fallback: .current)
    guard defaults.bool(forKey: DueSettings.enabledKey) else { return true }
    // Signed out: nothing to ask, nothing to schedule.
    guard let token = session.token() else { return true }
    var keepGoing = true
    var done = true
    let status = await center.notificationSettings().authorizationStatus
    // Nothing could be said: nothing is asked of the server either. Tomorrow's run looks again.
    if NoticesChannel.permission(status) == "granted",
      let server = DueToday.server(session.server(), fallback: KeychainSession.defaultServer)
    {
      let api = DueApi(server: server, token: token)
      let run = await DueToday.run(
        now: Date(), known: zone, lastDay: defaults.string(forKey: DueSettings.lastDayKey),
        get: api.get)
      zone = run.zone
      keepGoing = run.keepGoing
      done = run.outcome != .failed
      if defaults.string(forKey: DueSettings.zoneKey) != zone.identifier {
        defaults.set(zone.identifier, forKey: DueSettings.zoneKey)
      }
      // Signed out, or the switch turned off, while the requests were on their way: nothing is said.
      if case .due(let names) = run.outcome, session.token() == token,
        defaults.bool(forKey: DueSettings.enabledKey),
        await post(names, language: defaults.string(forKey: DueSettings.languageKey), center: center)
      {
        defaults.set(run.today, forKey: DueSettings.lastDayKey)
      }
    }
    // Tomorrow's 9:00 (or today's, when this run came before it), as the last step: only while the
    // switch is on and someone is signed in.
    if keepGoing, defaults.bool(forKey: DueSettings.enabledKey), session.token() != nil {
      schedule(zone: zone)
    }
    return done
  }

  /// Posts the notice now, in place of an earlier one; false when it could not.
  private static func post(_ names: [String], language: String?, center: UNUserNotificationCenter)
    async -> Bool
  {
    let body = DueToday.text(
      names,
      one: NoticePoster.text("notice_due_one", language: language),
      many: NoticePoster.text("notice_due_many", language: language),
      and: NoticePoster.text("notice_and", language: language),
      andI: NoticePoster.text("notice_and_i", language: language))
    guard !body.isEmpty else { return false }
    let content = UNMutableNotificationContent()
    content.title = NoticePoster.title
    content.body = body
    content.sound = .default
    // Home, with the payments due today.
    content.userInfo = ["link": "due"]
    let request = UNNotificationRequest(
      identifier: NoticePoster.dueId, content: content, trigger: nil)
    do {
      try await center.add(request)
      return true
    } catch {
      return false
    }
  }
}

/// The two reads of a run, as the app makes them (lib/api/client.dart): `<server>/api`, the bearer
/// token, the phone's zone and language; `x-wambito-background: 1` keeps them from counting as
/// activity. Redirects are not followed (the token stays with the server it was meant for).
private struct DueApi {
  let server: String
  let token: String

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
  }()

  func get(_ path: String) async -> DueToday.Answer {
    guard let url = DueToday.url(server: server, path: path) else { return .failed }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "x-wambito-background")
    request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-wambito-timezone")
    request.setValue(Locale.current.identifier(.bcp47), forHTTPHeaderField: "x-wambito-locale")
    do {
      let (data, response) = try await Self.session.data(for: request, delegate: NoRedirects.shared)
      switch (response as? HTTPURLResponse)?.statusCode {
      case 200: return .ok(data)
      case 401: return .unauthorized
      default: return .failed
      }
    } catch {
      return .failed
    }
  }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
  static let shared = NoRedirects()

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
