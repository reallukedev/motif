import CloudKit
import Foundation
import Testing
@testable import MotifCore

/// Telling a store that opened with sync apart from one that is actually syncing.
@MainActor
@Suite("iCloud sync health")
struct CloudSyncMonitorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a refused export is reported")
    func exportFailureIsReported() throws {
        let monitor = CloudSyncMonitor()

        monitor.record(.export, succeeded: false, message: "Refused", at: start)

        let failure = try #require(monitor.failure)
        #expect(failure.activity == .export)
        #expect(failure.message == "Refused")
        #expect(failure.date == start)
    }

    /// The Mac imported nothing while every export was refused. A success of a different kind
    /// must not make that look fixed.
    @Test("a success of another kind leaves the failure showing")
    func otherSuccessKeepsFailure() {
        let monitor = CloudSyncMonitor()

        monitor.record(.export, succeeded: false, message: "Refused", at: start)
        monitor.record(.import, succeeded: true, message: nil, at: start.addingTimeInterval(1))

        #expect(monitor.failure?.activity == .export)
    }

    @Test("a success of the same kind clears the failure")
    func sameSuccessClearsFailure() {
        let monitor = CloudSyncMonitor()

        monitor.record(.export, succeeded: false, message: "Refused", at: start)
        monitor.record(.export, succeeded: true, message: nil, at: start.addingTimeInterval(1))

        #expect(monitor.failure == nil)
    }

    @Test("a failure with no error still says something")
    func failureWithoutMessage() throws {
        let monitor = CloudSyncMonitor()

        monitor.record(.setup, succeeded: false, message: nil, at: start)

        let failure = try #require(monitor.failure)
        #expect(!failure.message.isEmpty)
    }

    /// What the Mac actually got: one record's reason, buried among the rest of the batch.
    @Test("a partial failure is described by the record that caused it")
    func partialFailureUsesTheCause() {
        let cause = "Cannot create or modify field 'CD_scrobbledAt' in record 'CD_Capture' in production schema"
        let error = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [
                CKRecord.ID(recordName: "a"): CKError(.batchRequestFailed),
                CKRecord.ID(recordName: "b"): CKError(
                    .invalidArguments,
                    userInfo: [NSLocalizedDescriptionKey: cause]
                ),
                CKRecord.ID(recordName: "c"): CKError(.batchRequestFailed),
            ] as [CKRecord.ID: any Error],
        ])

        #expect(CloudSyncMonitor.message(for: error) == cause)
    }

    /// The mirror's event keeps only "CKErrorDomain error 2", so the reason comes from the
    /// line CloudKit logged. This is that line, as the Mac logged it.
    @Test("the server's reason is read out of a logged CloudKit error")
    func serverMessageFromLog() {
        let logged = """
            Finished operation <CKModifyRecordsOperation: 0x77ad9fcf00> with error: <CKError 0x77ada9b750: \
            "Partial Failure" (2/1011); "Failed to modify some records"; partial errors: {
            \tA95663E0:(com.apple.coredata.cloudkit.zone:__defaultOwner__) = <CKError 0x77ada9b300: \
            "Invalid Arguments" (12/2006); server message = "Cannot create or modify field 'CD_deviceID' \
            in record 'CD_Session' in production schema"; op = ACABE99432842D30>
            \t... 2 "Batch Request Failed" CKErrors omitted ...
            }>
            """

        #expect(
            CloudSyncMonitor.serverMessage(in: logged)
                == "Cannot create or modify field 'CD_deviceID' in record 'CD_Session' in production schema"
        )
    }

    @Test("a log line without a server message gives nothing")
    func noServerMessage() {
        #expect(CloudSyncMonitor.serverMessage(in: "Finished operation <CKFetchDatabaseChangesOperation>") == nil)
    }

    @Test("any other error is described as it is")
    func plainError() {
        let error = CKError(.networkUnavailable, userInfo: [NSLocalizedDescriptionKey: "Offline"])

        #expect(CloudSyncMonitor.message(for: error) == "Offline")
    }
}
