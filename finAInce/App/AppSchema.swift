import SwiftData

// ============================================================
// GUIA DE MIGRAÇÃO — LEIA ANTES DE ALTERAR QUALQUER @Model
// ============================================================
//
// REGRA DE OURO: nunca altere um @Model sem criar um novo
// schema version. Caso contrário, o SwiftData apaga TODOS
// os dados do usuário ao atualizar o app.
//
// ── O QUE EXIGE NOVA VERSÃO ────────────────────────────────
//  ✅ Adicionar propriedade opcional        → lightweight
//  ✅ Adicionar propriedade com valor padrão → lightweight
//  ✅ Adicionar novo @Model                  → lightweight
//  ✅ Renomear propriedade                   → lightweight
//     (usar @Attribute(.renamingIdentifier("nomeAntigo")))
//  ⚠️  Remover propriedade                  → lightweight
//     (dados são perdidos, mas sem crash)
//  🔴 Mudar tipo de propriedade             → custom migration
//  🔴 Mover dados entre models              → custom migration
//
// ── COMO ADICIONAR UMA NOVA VERSÃO ────────────────────────
//
//  1. Crie SchemaV2 abaixo (copie o models array de SchemaV1
//     e ajuste o versionIdentifier):
//
//     enum SchemaV2: VersionedSchema {
//         static var versionIdentifier = Schema.Version(1, 1, 0)
//         static var models: [any PersistentModel.Type] = [
//             ... mesmos models + eventuais novos ...
//         ]
//     }
//
//  2. Adicione um MigrationStage em AppMigrationPlan:
//
//     static let v1ToV2 = MigrationStage.lightweight(
//         fromVersion: SchemaV1.self,
//         toVersion:   SchemaV2.self
//     )
//
//  3. Atualize as duas arrays em AppMigrationPlan:
//
//     static var schemas: [...] = [SchemaV1.self, SchemaV2.self]
//     static var stages:  [...] = [v1ToV2]
//
//  ⚠️  NUNCA remova versões antigas de `schemas` — o SwiftData
//  precisa do caminho completo para migrar usuários que pularam
//  versões (ex: instalaram V1 e pularam direto para V3).
// ============================================================

// MARK: - Schema V1 — Estado inicial do app (versão 1.0.0)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Family.self,
        Account.self,
        Category.self,
        Transaction.self,
        AISettings.self,
        AIAnalysis.self,
        ChatConversation.self,
        ChatMessage.self,
        Goal.self
    ]
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] = [
        Family.self,
        Account.self,
        Category.self,
        Transaction.self,
        ReceiptAttachment.self,
        AISettings.self,
        AIAnalysis.self,
        ChatConversation.self,
        ChatMessage.self,
        Goal.self
    ]
}

// MARK: - Migration Plan
//
// Nota: propriedades opcionais adicionadas a um @Model existente (ex: importHash)
// são migradas automaticamente pelo SwiftData sem necessidade de um novo schema
// ou migration stage explícito. Adicione SchemaV2 apenas para mudanças que
// exijam migração customizada (renomear propriedade, mudar tipo, mover dados).

enum AppMigrationPlan: SchemaMigrationPlan {
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    // ⚠️  Mantenha TODAS as versões aqui — nunca remova uma versão antiga.
    static var schemas: [any VersionedSchema.Type] = [
        SchemaV1.self,
        SchemaV2.self
    ]

    // Adicione os stages na mesma ordem cronológica das versões.
    static var stages: [MigrationStage] = [
        v1ToV2
    ]
}
