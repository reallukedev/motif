import CloudKit
import CoreData
import Foundation
import Observation
import OSLog

/// What the CloudKit mirror last said about itself.
///
/// A store that opened with sync can still fail to sync. The container opens, and only
/// afterwards does the mirror find out CloudKit won't take its records — as happened when
/// the Production schema was missing `CD_scrobbledAt`. Every export failed, setup never
/// finished, nothing was imported, and Settings still said "On", while the Mac and the iPhone
/// quietly grew two different histories. This listens to the events the mirror posts so that
/// failure can be shown.
@MainActor
@Observable
public final class CloudSyncMonitor {

    /// One of the mirror's three kinds of work.
    public enum Activity: String, Sendable, Equatable {
        case setup, `import`, export
    }

    public struct Failure: Sendable, Equatable {
        public let activity: Activity
        public let message: String
        public let date: Date
    }

    /// The most recent failure that nothing of the same kind has succeeded since, if any.
    public private(set) var failure: Failure?

    @ObservationIgnored private var observer: NSObjectProtocol?

    public init() {}

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Starts listening. Call it before the store opens: setup is reported as soon as the
    /// container is made, and a setup failure is the one that stops everything else.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                  let activity = Activity(event.type),
                  // Posted once when the work starts and again when it ends.
                  let endDate = event.endDate
            else { return }
            let succeeded = event.succeeded
            let startDate = event.startDate
            let message = event.error.map(Self.message(for:))
            MainActor.assumeIsolated {
                self?.record(activity, succeeded: succeeded, message: message, at: endDate)
                if !succeeded { self?.explainFailure(since: startDate) }
            }
        }
    }

    /// Replaces the event's bare error with CloudKit's own reason, if the log has one.
    ///
    /// The event only keeps an error's domain and code, so a refused save reaches here as
    /// "CKErrorDomain error 2" with the reason gone. CloudKit logs the server's message for
    /// each refused record, in this process, where the app can read it back.
    private func explainFailure(since start: Date) {
        guard let failure else { return }
        Task {
            guard let reason = await Self.loggedServerMessage(since: start),
                  self.failure == failure
            else { return }
            self.failure = Failure(activity: failure.activity, message: reason, date: failure.date)
        }
    }

    /// The last server message CloudKit logged in this process since `start`.
    @concurrent
    nonisolated static func loggedServerMessage(since start: Date) async -> String? {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(
                  at: store.position(date: start.addingTimeInterval(-5)),
                  matching: NSPredicate(format: "subsystem == %@", "com.apple.cloudkit")
              )
        else { return nil }
        var latest: String?
        for case let entry as OSLogEntryLog in entries {
            if let message = serverMessage(in: entry.composedMessage) { latest = message }
        }
        return latest
    }

    /// Pulls `server message = "…"` out of a logged CloudKit error.
    nonisolated static func serverMessage(in text: String) -> String? {
        let marker = "server message = \""
        guard let start = text.range(of: marker)?.upperBound,
              let end = text[start...].firstIndex(of: "\"")
        else { return nil }
        let message = text[start..<end]
        return message.isEmpty ? nil : String(message)
    }

    /// Folds in one finished piece of work.
    ///
    /// A success clears only a failure of the same kind. An import can succeed while every
    /// export is being refused, and that must still show.
    func record(_ activity: Activity, succeeded: Bool, message: String?, at date: Date) {
        if succeeded {
            if failure?.activity == activity { failure = nil }
            return
        }
        failure = Failure(
            activity: activity,
            message: message ?? "iCloud reported a problem without saying what it was.",
            date: date
        )
    }

    /// The most useful sentence out of a CloudKit error.
    ///
    /// A refused save arrives as a partial failure whose own description is only "Failed to
    /// modify some records". The reason is on one of the records inside it, surrounded by
    /// dozens of "Batch Request Failed" errors that only mean they were sent alongside it.
    public nonisolated static func message(for error: any Error) -> String {
        if let error = error as? CKError,
           let partial = error.partialErrorsByItemID?.values
               .compactMap({ $0 as? CKError })
               .filter({ $0.code != .batchRequestFailed })
               // Dictionary order isn't stable, so pick the same one every time.
               .min(by: { $0.localizedDescription < $1.localizedDescription }) {
            return partial.localizedDescription
        }
        return error.localizedDescription
    }
}

extension CloudSyncMonitor.Activity {
    init?(_ type: NSPersistentCloudKitContainer.EventType) {
        switch type {
        case .setup: self = .setup
        case .import: self = .import
        case .export: self = .export
        @unknown default: return nil
        }
    }
}
