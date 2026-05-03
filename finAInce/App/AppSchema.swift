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
//  1. Crie SchemaV3 abaixo (copie o models array de SchemaV2
//     e ajuste o versionIdentifier):
//
//     enum SchemaV3: VersionedSchema {
//         static var versionIdentifier = Schema.Version(3, 0, 0)
//         static var models: [any PersistentModel.Type] = [
//             ... mesmos models + eventuais novos ...
//         ]
//     }
//
//  2. Adicione um MigrationStage em AppMigrationPlan:
//
//     static let v2ToV3 = MigrationStage.lightweight(
//         fromVersion: SchemaV2.self,
//         toVersion:   SchemaV3.self
//     )
//
//  3. Atualize as duas arrays em AppMigrationPlan:
//
//     static var schemas: [...] = [SchemaV1.self, SchemaV2.self, SchemaV3.self]
//     static var stages:  [...] = [v1ToV2, v2ToV3]
//
//  ⚠️  NUNCA remova versões antigas de `schemas` — o SwiftData
//  precisa do caminho completo para migrar usuários que pularam
//  versões (ex: instalaram V1 e pularam direto para V3).
//
// ── NOTA SOBRE CHECKSUMS ──────────────────────────────────
//  O SwiftData calcula o checksum de cada VersionedSchema
//  com base no conjunto de model types referenciados.
//  Dois schemas com exatamente os mesmos types (mesmo que
//  definidos como versões diferentes) geram checksums
//  idênticos → erro "Duplicate version checksums detected".
//  Por isso, cada versão deve ter pelo menos um model
//  diferente em relação à versão anterior.
// ============================================================

// MARK: - Schema V1 — Estado inicial (sem ReceiptAttachment)

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

// MARK: - Schema V2 — Estado atual
//
// Mudanças em relação a V1:
//  • Adicionado ReceiptAttachment
//  • Removido @Attribute(.unique) de todos os ids (CloudKit não suporta)
//
// V2 é o estado compilado atual — qualquer nova alteração
// deve criar um SchemaV3 acima desta definição.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Family.self,
        Account.self,
        Category.self,
        Transaction.self,
        CashWithdrawalAllocation.self,
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
// ⚠️  NÃO USAR migration plan explícito enquanto os model types forem
// reutilizados entre versões (ex: SchemaV1 e SchemaV2 referenciam os
// mesmos Family.self, Account.self etc. compilados).
// SwiftData calcula o checksum por model type — types idênticos em duas
// versões geram "Duplicate version checksums detected" → crash.
//
// O ModelContainer usa auto-migração (sem migrationPlan:) que resolve
// lightweight changes (adicionar model, remover .unique) automaticamente.
//
// Para usar migration plan explícito no futuro, cada VersionedSchema deve
// referenciar subtipos próprios (ex: SchemaV2.Family vs SchemaV1.Family),
// seguindo o padrão oficial da Apple — veja a WWDC23 session "Migrate to
// SwiftData" para detalhes.

enum AppMigrationPlan: SchemaMigrationPlan {
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    static var schemas: [any VersionedSchema.Type] = [
        SchemaV1.self,
        SchemaV2.self
    ]

    static var stages: [MigrationStage] = [
        v1ToV2
    ]
}
