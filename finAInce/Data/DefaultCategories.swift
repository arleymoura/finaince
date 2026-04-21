import Foundation
import SwiftData

/// Popula as categorias e subcategorias padrão do sistema no primeiro uso.
struct DefaultCategories {

    struct CategoryDefinition {
        let name: String
        let icon: String
        let color: String
        let type: CategoryType
        let sortOrder: Int
        let subcategories: [SubcategoryDefinition]
    }

    struct SubcategoryDefinition {
        let name: String
        let icon: String
        let sortOrder: Int
    }

    // MARK: - Seed

    static func seed(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existingCategories = (try? modelContext.fetch(descriptor)) ?? []

        for def in all {
            let category = existingRootCategory(matching: def, in: existingCategories) ?? {
                let category = Category(
                    name: def.name,
                    icon: def.icon,
                    color: def.color,
                    type: def.type,
                    isSystem: true,
                    sortOrder: def.sortOrder
                )
                modelContext.insert(category)
                return category
            }()

            category.icon = def.icon
            category.color = def.color
            category.type = def.type
            category.isSystem = true
            category.sortOrder = def.sortOrder

            for subDef in def.subcategories {
                if let existingSubcategory = existingSubcategory(
                    matching: subDef,
                    parent: category,
                    type: def.type,
                    in: existingCategories
                ) {
                    existingSubcategory.icon = subDef.icon
                    existingSubcategory.color = def.color
                    existingSubcategory.type = def.type
                    existingSubcategory.isSystem = true
                    existingSubcategory.sortOrder = subDef.sortOrder
                    existingSubcategory.parent = category
                    continue
                }

                let subcategory = Category(
                    name: subDef.name,
                    icon: subDef.icon,
                    color: def.color,
                    type: def.type,
                    isSystem: true,
                    sortOrder: subDef.sortOrder,
                    parent: category
                )
                modelContext.insert(subcategory)
            }
        }
    }

    private static func existingRootCategory(
        matching definition: CategoryDefinition,
        in categories: [Category]
    ) -> Category? {
        categories.first {
            $0.parent == nil
                && $0.type == definition.type
                && $0.name.normalizedForMatching() == definition.name.normalizedForMatching()
        }
    }

    private static func existingSubcategory(
        matching definition: SubcategoryDefinition,
        parent: Category,
        type: CategoryType,
        in categories: [Category]
    ) -> Category? {
        categories.first {
            guard let existingParent = $0.parent else { return false }

            return existingParent.persistentModelID == parent.persistentModelID
                && $0.type == type
                && $0.name.normalizedForMatching() == definition.name.normalizedForMatching()
        }
    }

    // MARK: - Definitions

    static let all: [CategoryDefinition] = [

        .init(name: "Moradia", icon: "house.fill", color: "#5E5CE6", type: .expense, sortOrder: 0, subcategories: [
            .init(name: "Aluguel",          icon: "key.fill",                    sortOrder: 0),
            .init(name: "Financiamento",    icon: "building.columns.fill",       sortOrder: 1),
            .init(name: "Condomínio",       icon: "building.2.fill",             sortOrder: 2),
            .init(name: "IPTU",             icon: "doc.text.fill",               sortOrder: 3),
            .init(name: "Água",             icon: "drop.fill",                   sortOrder: 4),
            .init(name: "Energia",          icon: "bolt.fill",                   sortOrder: 5),
            .init(name: "Gás",              icon: "flame.fill",                  sortOrder: 6),
            .init(name: "Comunicação",      icon: "antenna.radiowaves.left.and.right", sortOrder: 7),
            .init(name: "Internet",         icon: "wifi",                        sortOrder: 8),
            .init(name: "TV / Streaming",   icon: "tv.fill",                     sortOrder: 9),
            .init(name: "Telefone",         icon: "phone.fill",                  sortOrder: 10),
        ]),

        .init(name: "Supermercado", icon: "cart.fill", color: "#FF9500", type: .expense, sortOrder: 1, subcategories: [
            .init(name: "Mercado",          icon: "cart.fill",                   sortOrder: 0),
            .init(name: "Feira",            icon: "leaf.fill",                   sortOrder: 1),
            .init(name: "Açougue",          icon: "flame.fill",                  sortOrder: 2),
            .init(name: "Padaria",          icon: "birthday.cake.fill",          sortOrder: 3),
            .init(name: "Hortifruti",       icon: "carrot.fill",                 sortOrder: 4),
        ]),

        .init(name: "Restaurantes", icon: "fork.knife", color: "#FF6B35", type: .expense, sortOrder: 2, subcategories: [
            .init(name: "Almoço / Jantar",  icon: "fork.knife",                  sortOrder: 0),
            .init(name: "Delivery",         icon: "bag.fill",                    sortOrder: 1),
            .init(name: "Fast Food",        icon: "takeoutbag.and.cup.and.straw.fill", sortOrder: 2),
            .init(name: "Café / Lanche",    icon: "cup.and.saucer.fill",         sortOrder: 3),
            .init(name: "Bares",            icon: "wineglass.fill",              sortOrder: 4),
        ]),

        .init(name: "Transporte", icon: "car.fill", color: "#007AFF", type: .expense, sortOrder: 3, subcategories: [
            .init(name: "Combustível",      icon: "fuelpump.fill",               sortOrder: 0),
            .init(name: "Estacionamento",   icon: "parkingsign.circle.fill",     sortOrder: 1),
            .init(name: "Ônibus / Metrô",   icon: "tram.fill",                   sortOrder: 2),
            .init(name: "Uber / Táxi",      icon: "car.circle.fill",             sortOrder: 3),
            .init(name: "IPVA",             icon: "doc.text.fill",               sortOrder: 4),
            .init(name: "Seguro Auto",      icon: "shield.fill",                 sortOrder: 5),
            .init(name: "Manutenção",       icon: "wrench.and.screwdriver.fill", sortOrder: 6),
            .init(name: "Pedágio",          icon: "road.lanes",                  sortOrder: 7),
        ]),

        .init(name: "Saúde", icon: "cross.case.fill", color: "#FF3B30", type: .expense, sortOrder: 4, subcategories: [
            .init(name: "Plano de Saúde",   icon: "heart.text.square.fill",      sortOrder: 0),
            .init(name: "Consulta",         icon: "stethoscope",                 sortOrder: 1),
            .init(name: "Farmácia",         icon: "pills.fill",                  sortOrder: 2),
            .init(name: "Exames",           icon: "testtube.2",                  sortOrder: 3),
            .init(name: "Dentista",         icon: "mouth.fill",                  sortOrder: 4),
        ]),

        .init(name: "Viagens", icon: "airplane", color: "#32ADE6", type: .expense, sortOrder: 5, subcategories: [
            .init(name: "Passagens",        icon: "airplane",                    sortOrder: 0),
            .init(name: "Hospedagem",       icon: "bed.double.fill",             sortOrder: 1),
            .init(name: "Passeios",         icon: "map.fill",                    sortOrder: 2),
            .init(name: "Aluguel de Carro", icon: "car.fill",                    sortOrder: 3),
            .init(name: "Bagagem",          icon: "suitcase.fill",               sortOrder: 4),
        ]),

        .init(name: "Educação", icon: "book.fill", color: "#34C759", type: .expense, sortOrder: 6, subcategories: [
            .init(name: "Escola",           icon: "graduationcap.fill",          sortOrder: 0),
            .init(name: "Cursos",           icon: "book.closed.fill",            sortOrder: 1),
            .init(name: "Material",         icon: "pencil.and.ruler.fill",       sortOrder: 2),
            .init(name: "Livros",           icon: "books.vertical.fill",         sortOrder: 3),
        ]),

        .init(name: "Lazer", icon: "gamecontroller.fill", color: "#AF52DE", type: .expense, sortOrder: 7, subcategories: [
            .init(name: "Cinema / Shows",   icon: "theatermasks.fill",           sortOrder: 0),
            .init(name: "Hobbies",          icon: "puzzlepiece.fill",            sortOrder: 1),
            .init(name: "Jogos",            icon: "gamecontroller.fill",         sortOrder: 3),
        ]),

        .init(name: "Shopping", icon: "bag.fill", color: "#FF2D55", type: .expense, sortOrder: 8, subcategories: [
            .init(name: "Roupas",           icon: "tshirt.fill",                 sortOrder: 0),
            .init(name: "Calçados",         icon: "shoeprints.fill",             sortOrder: 1),
            .init(name: "Acessórios",       icon: "bag.fill",                    sortOrder: 2),
            .init(name: "Presentes",        icon: "gift.fill",                   sortOrder: 3),
        ]),

        .init(name: "Pets", icon: "pawprint.fill", color: "#FF9F0A", type: .expense, sortOrder: 9, subcategories: [
            .init(name: "Ração",            icon: "bowl.fill",                   sortOrder: 0),
            .init(name: "Veterinário",      icon: "cross.vial.fill",             sortOrder: 1),
            .init(name: "Banho / Tosa",     icon: "shower.fill",                 sortOrder: 2),
            .init(name: "Pet Shop",         icon: "storefront.fill",             sortOrder: 3),
        ]),

        .init(name: "Cuidados Pessoais", icon: "face.smiling.fill", color: "#5AC8FA", type: .expense, sortOrder: 10, subcategories: [
            .init(name: "Cabelo / Beleza",  icon: "scissors",                    sortOrder: 0),
            .init(name: "Higiene",          icon: "shower.fill",                 sortOrder: 1),
            .init(name: "Cosméticos",       icon: "sparkles",                    sortOrder: 2),
            .init(name: "Profissionais",         icon: "circle.fill",                  sortOrder: 3),
        ]),

        .init(name: "Financeiro", icon: "banknote.fill", color: "#636366", type: .expense, sortOrder: 11, subcategories: [
            .init(name: "Juros / Taxas",    icon: "percent",                     sortOrder: 0),
            .init(name: "Seguros",          icon: "shield.fill",                 sortOrder: 1),
            .init(name: "Tarifas",          icon: "building.columns.fill",       sortOrder: 2),
            .init(name: "Empréstimo",       icon: "arrow.triangle.2.circlepath", sortOrder: 3),
            .init(name: "Impostos",         icon: "doc.text.fill",               sortOrder: 4),
        ]),

        .init(name: "Assinaturas", icon: "repeat.circle.fill", color: "#7D7AFF", type: .expense, sortOrder: 12, subcategories: [
            .init(name: "Streaming",        icon: "play.tv.fill",                sortOrder: 0),
            .init(name: "Música",           icon: "music.note",                  sortOrder: 1),
            .init(name: "SaaS",             icon: "laptopcomputer",              sortOrder: 2),
            .init(name: "Apps",             icon: "apps.iphone",                 sortOrder: 3),
            .init(name: "Cloud / Backup",   icon: "icloud.fill",                 sortOrder: 4),
            .init(name: "Jogos",            icon: "gamecontroller.fill",         sortOrder: 5),
        ]),

        .init(name: "Esportes", icon: "figure.run", color: "#30B0C7", type: .expense, sortOrder: 13, subcategories: [
            .init(name: "Academia",         icon: "dumbbell.fill",               sortOrder: 0),
            .init(name: "Corrida",          icon: "figure.run",                  sortOrder: 1),
            .init(name: "Futebol",          icon: "soccerball",                  sortOrder: 2),
            .init(name: "Tênis",            icon: "tennis.racket",               sortOrder: 3),
            .init(name: "Ciclismo",         icon: "bicycle",                     sortOrder: 4),
            .init(name: "Natação",          icon: "figure.pool.swim",            sortOrder: 5),
            .init(name: "Esportes em Geral", icon: "sportscourt.fill",           sortOrder: 6),
        ]),

        .init(name: "Outros", icon: "ellipsis.circle.fill", color: "#8E8E93", type: .expense, sortOrder: 14, subcategories: [
            .init(name: "Presentes",        icon: "gift.fill",                   sortOrder: 0),
            .init(name: "Doações",          icon: "heart.fill",                  sortOrder: 1),
            .init(name: "Outros",           icon: "ellipsis.circle.fill",        sortOrder: 2),
        ]),
    ]
}
