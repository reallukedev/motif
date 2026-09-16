import Foundation
import SwiftData

/// The store's first versioned schema.
///
/// Every build before this one opened the store with a bare `Schema`, so there is no earlier
/// version to name. SwiftData treats an unversioned store as whatever version its model
/// hashes match and infers a lightweight migration to this one, which covers what this
/// version added over the last unversioned build: `Session.deviceID` and the indexes.
///
/// It lists the live model classes because it is the only version. When the models next
/// change, freeze these as nested copies inside this enum, add `MotifSchemaV2` with the
/// live classes, and give ``MotifMigrationPlan`` a stage between them. CloudKit only
/// accepts additive changes (new optional or defaulted attributes, new models) once the
/// schema is in Production, so a custom stage is for local clean-up, never for renaming or
/// removing a synced field.
public enum MotifSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Capture.self, Station.self, Session.self, StatsSnapshot.self]
    }
}

/// How an existing store reaches the current schema. Every container is opened with it,
/// including the widget's read-only one, so they all agree on what version the file is.
public enum MotifMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [MotifSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
