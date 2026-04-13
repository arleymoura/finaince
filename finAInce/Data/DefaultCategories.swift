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
        for (index, def) in all.enumerated() {
            let category = Category(
                name: def.name,
                icon: def.icon,
                color: def.color,
                type: def.type,
                isSystem: true,
                sortOrder: index
            )
            modelContext.insert(category)

            for (subIndex, subDef) in def.subcategories.enumerated() {
                let sub = Category(
                    name: subDef.name,
                    icon: subDef.icon,
                    color: def.color,
                    type: def.type,
                    isSystem: true,
                    sortOrder: subIndex,
                    parent: category
                )
                modelContext.insert(sub)
            }
        }
    }

    // MARK: - Definitions

    static let all: [CategoryDefinition] = [

        // ── DESPESAS ─────────────────────────────────────────────────────

        .init(name: "Moradia", icon: "house.fill", color: "#5E5CE6", type: .expense, sortOrder: 0, subcategories: [
            .init(name: "Aluguel",          icon: "key.fill",                sortOrder: 0),
            .init(name: "Financiamento",    icon: "building.columns.fill",   sortOrder: 1),
            .init(name: "Condomínio",       icon: "building.2.fill",         sortOrder: 2),
            .init(name: "IPTU",             icon: "doc.text.fill",           sortOrder: 3),
            .init(name: "Água",             icon: "drop.fill",               sortOrder: 4),
            .init(name: "Energia",          icon: "bolt.fill",               sortOrder: 5),
            .init(name: "Gás",              icon: "flame.fill",              sortOrder: 6),
            .init(name: "Internet",         icon: "wifi",                    sortOrder: 7),
            .init(name: "TV / Streaming",   icon: "tv.fill",                 sortOrder: 8),
        ]),

        .init(name: "Alimentação", icon: "cart.fill", color: "#FF9500", type: .expense, sortOrder: 1, subcategories: [
            .init(name: "Supermercado",     icon: "cart.fill",               sortOrder: 0),
            .init(name: "Restaurante",      icon: "fork.knife",              sortOrder: 1),
            .init(name: "Delivery",         icon: "bag.fill",                sortOrder: 2),
            .init(name: "Padaria",          icon: "birthday.cake.fill",      sortOrder: 3),
            .init(name: "Feira",            icon: "leaf.fill",               sortOrder: 4),
            .init(name: "Açougue",          icon: "flame.fill",              sortOrder: 5),
        ]),

        .init(name: "Transporte", icon: "car.fill", color: "#007AFF", type: .expense, sortOrder: 2, subcategories: [
            .init(name: "Combustível",      icon: "fuelpump.fill",           sortOrder: 0),
            .init(name: "Estacionamento",   icon: "parkingsign.circle.fill", sortOrder: 1),
            .init(name: "Ônibus / Metrô",   icon: "tram.fill",               sortOrder: 2),
            .init(name: "Uber / Táxi",      icon: "car.circle.fill",         sortOrder: 3),
            .init(name: "IPVA",             icon: "doc.text.fill",           sortOrder: 4),
            .init(name: "Seguro Auto",      icon: "shield.fill",             sortOrder: 5),
            .init(name: "Manutenção",       icon: "wrench.and.screwdriver.fill", sortOrder: 6),
            .init(name: "Pedágio",          icon: "road.lanes",              sortOrder: 7),
        ]),

        .init(name: "Saúde", icon: "cross.case.fill", color: "#FF3B30", type: .expense, sortOrder: 3, subcategories: [
            .init(name: "Plano de Saúde",   icon: "heart.text.square.fill",  sortOrder: 0),
            .init(name: "Consulta",         icon: "stethoscope",             sortOrder: 1),
            .init(name: "Farmácia",         icon: "pills.fill",              sortOrder: 2),
            .init(name: "Exames",           icon: "testtube.2",              sortOrder: 3),
            .init(name: "Dentista",         icon: "mouth.fill",              sortOrder: 4),
            .init(name: "Academia",         icon: "figure.run",              sortOrder: 5),
        ]),

        .init(name: "Educação", icon: "book.fill", color: "#34C759", type: .expense, sortOrder: 4, subcategories: [
            .init(name: "Escola",           icon: "graduationcap.fill",      sortOrder: 0),
            .init(name: "Cursos",           icon: "book.closed.fill",        sortOrder: 1),
            .init(name: "Material",         icon: "pencil.and.ruler.fill",   sortOrder: 2),
            .init(name: "Livros",           icon: "books.vertical.fill",     sortOrder: 3),
        ]),

        .init(name: "Lazer", icon: "gamecontroller.fill", color: "#AF52DE", type: .expense, sortOrder: 5, subcategories: [
            .init(name: "Cinema / Shows",   icon: "theatermasks.fill",       sortOrder: 0),
            .init(name: "Viagens",          icon: "airplane",                sortOrder: 1),
            .init(name: "Hobbies",          icon: "puzzlepiece.fill",        sortOrder: 2),
            .init(name: "Assinaturas",      icon: "play.rectangle.fill",     sortOrder: 3),
            .init(name: "Bares",            icon: "wineglass.fill",          sortOrder: 4),
        ]),

        .init(name: "Vestuário", icon: "tshirt.fill", color: "#FF2D55", type: .expense, sortOrder: 6, subcategories: [
            .init(name: "Roupas",           icon: "tshirt.fill",             sortOrder: 0),
            .init(name: "Calçados",         icon: "shoeprints.fill",         sortOrder: 1),
            .init(name: "Acessórios",       icon: "bag.fill",                sortOrder: 2),
        ]),

        .init(name: "Pets", icon: "pawprint.fill", color: "#FF9F0A", type: .expense, sortOrder: 7, subcategories: [
            .init(name: "Ração",            icon: "bowl.fill",               sortOrder: 0),
            .init(name: "Veterinário",      icon: "cross.vial.fill",         sortOrder: 1),
            .init(name: "Banho / Tosa",     icon: "shower.fill",             sortOrder: 2),
            .init(name: "Pet Shop",         icon: "storefront.fill",         sortOrder: 3),
        ]),

        .init(name: "Cuidados Pessoais", icon: "face.smiling.fill", color: "#5AC8FA", type: .expense, sortOrder: 8, subcategories: [
            .init(name: "Cabelo / Beleza",  icon: "scissors",                sortOrder: 0),
            .init(name: "Higiene",          icon: "shower.fill",             sortOrder: 1),
            .init(name: "Cosméticos",       icon: "sparkles",                sortOrder: 2),
        ]),

        .init(name: "Financeiro", icon: "banknote.fill", color: "#636366", type: .expense, sortOrder: 9, subcategories: [
            .init(name: "Juros / Taxas",    icon: "percent",                 sortOrder: 0),
            .init(name: "Seguros",          icon: "shield.fill",             sortOrder: 1),
            .init(name: "Tarifas",          icon: "building.columns.fill",   sortOrder: 2),
            .init(name: "Empréstimo",       icon: "arrow.triangle.2.circlepath", sortOrder: 3),
        ]),

        .init(name: "Outros", icon: "ellipsis.circle.fill", color: "#8E8E93", type: .expense, sortOrder: 10, subcategories: [
            .init(name: "Presentes",        icon: "gift.fill",               sortOrder: 0),
            .init(name: "Doações",          icon: "heart.fill",              sortOrder: 1),
            .init(name: "Outros",           icon: "ellipsis.circle.fill",    sortOrder: 2),
        ]),

        // ── RECEITAS ─────────────────────────────────────────────────────

        .init(name: "Renda", icon: "dollarsign.circle.fill", color: "#34C759", type: .income, sortOrder: 11, subcategories: [
            .init(name: "Salário",          icon: "dollarsign.circle.fill",  sortOrder: 0),
            .init(name: "Freelance",        icon: "laptopcomputer",          sortOrder: 1),
            .init(name: "Bônus",            icon: "star.fill",               sortOrder: 2),
            .init(name: "13º Salário",      icon: "gift.fill",               sortOrder: 3),
            .init(name: "Hora Extra",       icon: "clock.fill",              sortOrder: 4),
        ]),

        .init(name: "Investimentos", icon: "chart.line.uptrend.xyaxis", color: "#30D158", type: .income, sortOrder: 12, subcategories: [
            .init(name: "Rendimentos",      icon: "chart.bar.fill",          sortOrder: 0),
            .init(name: "Dividendos",       icon: "arrow.up.right.circle.fill", sortOrder: 1),
            .init(name: "Venda de Ativos",  icon: "building.fill",           sortOrder: 2),
        ]),

        .init(name: "Outras Receitas", icon: "plus.circle.fill", color: "#00C7BE", type: .income, sortOrder: 13, subcategories: [
            .init(name: "Presente",         icon: "gift.fill",               sortOrder: 0),
            .init(name: "Reembolso",        icon: "arrow.uturn.left.circle.fill", sortOrder: 1),
            .init(name: "Outros",           icon: "ellipsis.circle.fill",    sortOrder: 2),
        ]),
    ]
}
