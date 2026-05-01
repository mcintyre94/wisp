import SwiftData

/// Schema V1 — original schema with SwiftData message persistence.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [SpriteChat.self, SpriteSession.self]
}

/// Schema V2 — wisplog as single source of truth.
/// Removes messagesData, streamEventUUIDsData, and lastSessionComplete from SpriteChat.
/// SpriteSession.messagesData is also unused from this version onward.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [SpriteChat.self, SpriteSession.self]
}

enum WispMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self]
    static var stages: [MigrationStage] = [v1ToV2]

    /// Lightweight migration: SwiftData drops the removed optional columns automatically.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
