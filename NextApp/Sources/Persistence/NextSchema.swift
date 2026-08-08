import Foundation
import SwiftData

/// Version 1 of the on-disk schema.
///
/// Declared explicitly, and with a migration plan, from the very first version. The point is not
/// that V1 needs migrating — it is that a store shipped without a versioned schema cannot be
/// migrated later without guessing what was there before. PRODUCT_SPEC.md §7 requires state to
/// survive ordinary version upgrades, and that promise is only keepable if the first release
/// already says what it wrote.
enum NextSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [StoredTask.self] }
}

/// How the store gets from one schema version to the next.
///
/// One stage-free version today. When V2 arrives, `StoredTask` moves inside each
/// `VersionedSchema` as a nested type with a `typealias` at the top level, so both shapes can
/// coexist during the migration — that restructuring is expected and is why this exists now
/// rather than later.
///
/// A round-trip test per schema version is required before release-candidate status
/// (`RELEASE_CHECKLIST.md`).
enum NextMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] { [NextSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
