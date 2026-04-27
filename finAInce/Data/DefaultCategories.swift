import Foundation
import SwiftData

/// Popula as categorias e subcategorias padrão do sistema no primeiro uso.
struct DefaultCategories {

    struct CategoryDefinition {
        let name: String
        let systemKey: String
        let icon: String
        let color: String
        let type: CategoryType
        let sortOrder: Int
        let subcategories: [SubcategoryDefinition]
    }

    struct SubcategoryDefinition {
        let name: String
        let systemKey: String
        let icon: String
        let sortOrder: Int
    }

    private static func names(
        _ ptBR: String,
        _ en: String,
        _ es: String
    ) -> [AppLanguage: String] {
        [
            .ptBR: ptBR,
            .en: en,
            .es: es
        ]
    }

    static func localizedName(for systemKey: String?, fallback: String) -> String {
        guard
            let systemKey,
            let translations = localizedNames[systemKey]
        else {
            return fallback
        }

        let language = LanguageManager.shared.effective
        return translations[language] ?? translations[.ptBR] ?? fallback
    }

    static let otherCategorySystemKey = "other"

    static func category(
        withSystemKey systemKey: String,
        in categories: [Category]
    ) -> Category? {
        categories.first {
            $0.parent == nil && $0.systemKey == systemKey
        }
    }

    static func subcategory(
        withSystemKey systemKey: String,
        parentSystemKey: String,
        in categories: [Category]
    ) -> Category? {
        categories.first {
            $0.systemKey == systemKey && $0.parent?.systemKey == parentSystemKey
        }
    }

    // MARK: - Seed

    static func seed(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existingCategories = (try? modelContext.fetch(descriptor)) ?? []

        for def in all {
            let category = existingRootCategory(matching: def, in: existingCategories) ?? {
                let category = Category(
                    name: def.name,
                    systemKey: def.systemKey,
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
            category.systemKey = def.systemKey
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
                    existingSubcategory.systemKey = subDef.systemKey
                    existingSubcategory.color = def.color
                    existingSubcategory.type = def.type
                    existingSubcategory.isSystem = true
                    existingSubcategory.sortOrder = subDef.sortOrder
                    existingSubcategory.parent = category
                    continue
                }

                let subcategory = Category(
                    name: subDef.name,
                    systemKey: subDef.systemKey,
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
                && (
                    $0.systemKey == definition.systemKey
                    || $0.name.normalizedForMatching() == definition.name.normalizedForMatching()
                )
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
                && (
                    $0.systemKey == definition.systemKey
                    || $0.name.normalizedForMatching() == definition.name.normalizedForMatching()
                )
        }
    }

    // MARK: - Definitions

    static let all: [CategoryDefinition] = [

        .init(name: "Moradia", systemKey: "housing", icon: "house.fill", color: "#5E5CE6", type: .expense, sortOrder: 0, subcategories: [
            .init(name: "Aluguel", systemKey: "housing.rent", icon: "key.fill", sortOrder: 0),
            .init(name: "Financiamento", systemKey: "housing.mortgage", icon: "building.columns.fill", sortOrder: 1),
            .init(name: "Condomínio", systemKey: "housing.condo", icon: "building.2.fill", sortOrder: 2),
            .init(name: "IPTU", systemKey: "housing.propertyTax", icon: "doc.text.fill", sortOrder: 3),
            .init(name: "Água", systemKey: "housing.water", icon: "drop.fill", sortOrder: 4),
            .init(name: "Energia", systemKey: "housing.energy", icon: "bolt.fill", sortOrder: 5),
            .init(name: "Gás", systemKey: "housing.gas", icon: "flame.fill", sortOrder: 6),
            .init(name: "Comunicação", systemKey: "housing.communication", icon: "antenna.radiowaves.left.and.right", sortOrder: 7),
            .init(name: "Internet", systemKey: "housing.internet", icon: "wifi", sortOrder: 8),
            .init(name: "TV / Streaming", systemKey: "housing.tvStreaming", icon: "tv.fill", sortOrder: 9),
            .init(name: "Telefone", systemKey: "housing.phone", icon: "phone.fill", sortOrder: 10),
        ]),

        .init(name: "Supermercado", systemKey: "groceries", icon: "cart.fill", color: "#FF9500", type: .expense, sortOrder: 1, subcategories: [
            .init(name: "Mercado", systemKey: "groceries.market", icon: "cart.fill", sortOrder: 0),
            .init(name: "Feira", systemKey: "groceries.fair", icon: "leaf.fill", sortOrder: 1),
            .init(name: "Açougue", systemKey: "groceries.butcher", icon: "flame.fill", sortOrder: 2),
            .init(name: "Padaria", systemKey: "groceries.bakery", icon: "birthday.cake.fill", sortOrder: 3),
            .init(name: "Hortifruti", systemKey: "groceries.produce", icon: "carrot.fill", sortOrder: 4),
        ]),

        .init(name: "Restaurantes", systemKey: "restaurants", icon: "fork.knife", color: "#FF6B35", type: .expense, sortOrder: 2, subcategories: [
            .init(name: "Almoço / Jantar", systemKey: "restaurants.lunchDinner", icon: "fork.knife", sortOrder: 0),
            .init(name: "Delivery", systemKey: "restaurants.delivery", icon: "bag.fill", sortOrder: 1),
            .init(name: "Fast Food", systemKey: "restaurants.fastFood", icon: "takeoutbag.and.cup.and.straw.fill", sortOrder: 2),
            .init(name: "Café / Lanche", systemKey: "restaurants.coffeeSnack", icon: "cup.and.saucer.fill", sortOrder: 3),
            .init(name: "Bares", systemKey: "restaurants.bars", icon: "wineglass.fill", sortOrder: 4),
        ]),

        .init(name: "Transporte", systemKey: "transport", icon: "car.fill", color: "#007AFF", type: .expense, sortOrder: 3, subcategories: [
            .init(name: "Combustível", systemKey: "transport.fuel", icon: "fuelpump.fill", sortOrder: 0),
            .init(name: "Estacionamento", systemKey: "transport.parking", icon: "parkingsign.circle.fill", sortOrder: 1),
            .init(name: "Ônibus / Metrô", systemKey: "transport.publicTransit", icon: "tram.fill", sortOrder: 2),
            .init(name: "Uber / Táxi", systemKey: "transport.rideHailing", icon: "car.circle.fill", sortOrder: 3),
            .init(name: "IPVA", systemKey: "transport.vehicleTax", icon: "doc.text.fill", sortOrder: 4),
            .init(name: "Seguro Auto", systemKey: "transport.carInsurance", icon: "shield.fill", sortOrder: 5),
            .init(name: "Manutenção", systemKey: "transport.maintenance", icon: "wrench.and.screwdriver.fill", sortOrder: 6),
            .init(name: "Pedágio", systemKey: "transport.tolls", icon: "road.lanes", sortOrder: 7),
        ]),

        .init(name: "Saúde", systemKey: "health", icon: "cross.case.fill", color: "#FF3B30", type: .expense, sortOrder: 4, subcategories: [
            .init(name: "Plano de Saúde", systemKey: "health.insurance", icon: "heart.text.square.fill", sortOrder: 0),
            .init(name: "Consulta", systemKey: "health.consultation", icon: "stethoscope", sortOrder: 1),
            .init(name: "Farmácia", systemKey: "health.pharmacy", icon: "pills.fill", sortOrder: 2),
            .init(name: "Exames", systemKey: "health.tests", icon: "testtube.2", sortOrder: 3),
            .init(name: "Dentista", systemKey: "health.dentist", icon: "mouth.fill", sortOrder: 4),
        ]),

        .init(name: "Viagens", systemKey: "travel", icon: "airplane", color: "#32ADE6", type: .expense, sortOrder: 5, subcategories: [
            .init(name: "Passagens", systemKey: "travel.tickets", icon: "airplane", sortOrder: 0),
            .init(name: "Hospedagem", systemKey: "travel.lodging", icon: "bed.double.fill", sortOrder: 1),
            .init(name: "Passeios", systemKey: "travel.tours", icon: "map.fill", sortOrder: 2),
            .init(name: "Aluguel de Carro", systemKey: "travel.carRental", icon: "car.fill", sortOrder: 3),
            .init(name: "Bagagem", systemKey: "travel.baggage", icon: "suitcase.fill", sortOrder: 4),
        ]),

        .init(name: "Educação", systemKey: "education", icon: "book.fill", color: "#34C759", type: .expense, sortOrder: 6, subcategories: [
            .init(name: "Escola", systemKey: "education.school", icon: "graduationcap.fill", sortOrder: 0),
            .init(name: "Cursos", systemKey: "education.courses", icon: "book.closed.fill", sortOrder: 1),
            .init(name: "Material", systemKey: "education.supplies", icon: "pencil.and.ruler.fill", sortOrder: 2),
            .init(name: "Livros", systemKey: "education.books", icon: "books.vertical.fill", sortOrder: 3),
        ]),

        .init(name: "Lazer", systemKey: "leisure", icon: "gamecontroller.fill", color: "#AF52DE", type: .expense, sortOrder: 7, subcategories: [
            .init(name: "Cinema / Shows", systemKey: "leisure.moviesShows", icon: "theatermasks.fill", sortOrder: 0),
            .init(name: "Hobbies", systemKey: "leisure.hobbies", icon: "puzzlepiece.fill", sortOrder: 1),
            .init(name: "Jogos", systemKey: "leisure.games", icon: "gamecontroller.fill", sortOrder: 3),
        ]),

        .init(name: "Shopping", systemKey: "shopping", icon: "bag.fill", color: "#FF2D55", type: .expense, sortOrder: 8, subcategories: [
            .init(name: "Roupas", systemKey: "shopping.clothes", icon: "tshirt.fill", sortOrder: 0),
            .init(name: "Calçados", systemKey: "shopping.shoes", icon: "shoeprints.fill", sortOrder: 1),
            .init(name: "Acessórios", systemKey: "shopping.accessories", icon: "bag.fill", sortOrder: 2),
            .init(name: "Presentes", systemKey: "shopping.gifts", icon: "gift.fill", sortOrder: 3),
        ]),

        .init(name: "Pets", systemKey: "pets", icon: "pawprint.fill", color: "#FF9F0A", type: .expense, sortOrder: 9, subcategories: [
            .init(name: "Ração", systemKey: "pets.food", icon: "bowl.fill", sortOrder: 0),
            .init(name: "Veterinário", systemKey: "pets.vet", icon: "cross.vial.fill", sortOrder: 1),
            .init(name: "Banho / Tosa", systemKey: "pets.grooming", icon: "shower.fill", sortOrder: 2),
            .init(name: "Pet Shop", systemKey: "pets.store", icon: "storefront.fill", sortOrder: 3),
        ]),

        .init(name: "Cuidados Pessoais", systemKey: "personalCare", icon: "face.smiling.fill", color: "#5AC8FA", type: .expense, sortOrder: 10, subcategories: [
            .init(name: "Cabelo / Beleza", systemKey: "personalCare.hairBeauty", icon: "scissors", sortOrder: 0),
            .init(name: "Higiene", systemKey: "personalCare.hygiene", icon: "shower.fill", sortOrder: 1),
            .init(name: "Cosméticos", systemKey: "personalCare.cosmetics", icon: "sparkles", sortOrder: 2),
            .init(name: "Profissionais", systemKey: "personalCare.professionals", icon: "circle.fill", sortOrder: 3),
        ]),

        .init(name: "Financeiro", systemKey: "financial", icon: "banknote.fill", color: "#636366", type: .expense, sortOrder: 11, subcategories: [
            .init(name: "Juros / Taxas", systemKey: "financial.interestFees", icon: "percent", sortOrder: 0),
            .init(name: "Seguros", systemKey: "financial.insurance", icon: "shield.fill", sortOrder: 1),
            .init(name: "Tarifas", systemKey: "financial.bankFees", icon: "building.columns.fill", sortOrder: 2),
            .init(name: "Empréstimo", systemKey: "financial.loan", icon: "arrow.triangle.2.circlepath", sortOrder: 3),
            .init(name: "Impostos", systemKey: "financial.taxes", icon: "doc.text.fill", sortOrder: 4),
        ]),

        .init(name: "Assinaturas", systemKey: "subscriptions", icon: "repeat.circle.fill", color: "#7D7AFF", type: .expense, sortOrder: 12, subcategories: [
            .init(name: "Streaming", systemKey: "subscriptions.streaming", icon: "play.tv.fill", sortOrder: 0),
            .init(name: "Música", systemKey: "subscriptions.music", icon: "music.note", sortOrder: 1),
            .init(name: "SaaS", systemKey: "subscriptions.saas", icon: "laptopcomputer", sortOrder: 2),
            .init(name: "Apps", systemKey: "subscriptions.apps", icon: "apps.iphone", sortOrder: 3),
            .init(name: "Cloud / Backup", systemKey: "subscriptions.cloudBackup", icon: "icloud.fill", sortOrder: 4),
            .init(name: "Jogos", systemKey: "subscriptions.games", icon: "gamecontroller.fill", sortOrder: 5),
        ]),

        .init(name: "Esportes", systemKey: "sports", icon: "figure.run", color: "#30B0C7", type: .expense, sortOrder: 13, subcategories: [
            .init(name: "Academia", systemKey: "sports.gym", icon: "dumbbell.fill", sortOrder: 0),
            .init(name: "Corrida", systemKey: "sports.running", icon: "figure.run", sortOrder: 1),
            .init(name: "Futebol", systemKey: "sports.soccer", icon: "soccerball", sortOrder: 2),
            .init(name: "Tênis", systemKey: "sports.tennis", icon: "tennis.racket", sortOrder: 3),
            .init(name: "Ciclismo", systemKey: "sports.cycling", icon: "bicycle", sortOrder: 4),
            .init(name: "Natação", systemKey: "sports.swimming", icon: "figure.pool.swim", sortOrder: 5),
            .init(name: "Esportes em Geral", systemKey: "sports.general", icon: "sportscourt.fill", sortOrder: 6),
        ]),

        .init(name: "Outros", systemKey: "other", icon: "ellipsis.circle.fill", color: "#8E8E93", type: .expense, sortOrder: 14, subcategories: [
            .init(name: "Presentes", systemKey: "other.gifts", icon: "gift.fill", sortOrder: 0),
            .init(name: "Doações", systemKey: "other.donations", icon: "heart.fill", sortOrder: 1),
            .init(name: "Outros", systemKey: "other.misc", icon: "ellipsis.circle.fill", sortOrder: 2),
        ]),
    ]

    private static let localizedNames: [String: [AppLanguage: String]] = [
        "housing": names("Moradia", "Housing", "Vivienda"),
        "housing.rent": names("Aluguel", "Rent", "Alquiler"),
        "housing.mortgage": names("Financiamento", "Mortgage", "Hipoteca"),
        "housing.condo": names("Condomínio", "Condo fee", "Condominio"),
        "housing.propertyTax": names("IPTU", "Property tax", "Impuesto inmobiliario"),
        "housing.water": names("Água", "Water", "Agua"),
        "housing.energy": names("Energia", "Electricity", "Electricidad"),
        "housing.gas": names("Gás", "Gas", "Gas"),
        "housing.communication": names("Comunicação", "Communication", "Comunicación"),
        "housing.internet": names("Internet", "Internet", "Internet"),
        "housing.tvStreaming": names("TV / Streaming", "TV / Streaming", "TV / Streaming"),
        "housing.phone": names("Telefone", "Phone", "Teléfono"),
        "groceries": names("Supermercado", "Groceries", "Supermercado"),
        "groceries.market": names("Mercado", "Market", "Mercado"),
        "groceries.fair": names("Feira", "Farmers market", "Feria"),
        "groceries.butcher": names("Açougue", "Butcher", "Carnicería"),
        "groceries.bakery": names("Padaria", "Bakery", "Panadería"),
        "groceries.produce": names("Hortifruti", "Produce", "Frutas y verduras"),
        "restaurants": names("Restaurantes", "Restaurants", "Restaurantes"),
        "restaurants.lunchDinner": names("Almoço / Jantar", "Lunch / Dinner", "Almuerzo / Cena"),
        "restaurants.delivery": names("Delivery", "Delivery", "Delivery"),
        "restaurants.fastFood": names("Fast Food", "Fast Food", "Comida rápida"),
        "restaurants.coffeeSnack": names("Café / Lanche", "Coffee / Snack", "Café / Merienda"),
        "restaurants.bars": names("Bares", "Bars", "Bares"),
        "transport": names("Transporte", "Transport", "Transporte"),
        "transport.fuel": names("Combustível", "Fuel", "Combustible"),
        "transport.parking": names("Estacionamento", "Parking", "Estacionamiento"),
        "transport.publicTransit": names("Ônibus / Metrô", "Bus / Subway", "Bus / Metro"),
        "transport.rideHailing": names("Uber / Táxi", "Uber / Taxi", "Uber / Taxi"),
        "transport.vehicleTax": names("IPVA", "Vehicle tax", "Impuesto vehicular"),
        "transport.carInsurance": names("Seguro Auto", "Car insurance", "Seguro del auto"),
        "transport.maintenance": names("Manutenção", "Maintenance", "Mantenimiento"),
        "transport.tolls": names("Pedágio", "Tolls", "Peajes"),
        "health": names("Saúde", "Health", "Salud"),
        "health.insurance": names("Plano de Saúde", "Health insurance", "Seguro médico"),
        "health.consultation": names("Consulta", "Consultation", "Consulta"),
        "health.pharmacy": names("Farmácia", "Pharmacy", "Farmacia"),
        "health.tests": names("Exames", "Tests", "Exámenes"),
        "health.dentist": names("Dentista", "Dentist", "Dentista"),
        "travel": names("Viagens", "Travel", "Viajes"),
        "travel.tickets": names("Passagens", "Tickets", "Pasajes"),
        "travel.lodging": names("Hospedagem", "Lodging", "Hospedaje"),
        "travel.tours": names("Passeios", "Tours", "Paseos"),
        "travel.carRental": names("Aluguel de Carro", "Car rental", "Alquiler de auto"),
        "travel.baggage": names("Bagagem", "Baggage", "Equipaje"),
        "education": names("Educação", "Education", "Educación"),
        "education.school": names("Escola", "School", "Escuela"),
        "education.courses": names("Cursos", "Courses", "Cursos"),
        "education.supplies": names("Material", "Supplies", "Materiales"),
        "education.books": names("Livros", "Books", "Libros"),
        "leisure": names("Lazer", "Leisure", "Ocio"),
        "leisure.moviesShows": names("Cinema / Shows", "Movies / Shows", "Cine / Espectáculos"),
        "leisure.hobbies": names("Hobbies", "Hobbies", "Pasatiempos"),
        "leisure.games": names("Jogos", "Games", "Juegos"),
        "shopping": names("Shopping", "Shopping", "Compras"),
        "shopping.clothes": names("Roupas", "Clothes", "Ropa"),
        "shopping.shoes": names("Calçados", "Shoes", "Calzado"),
        "shopping.accessories": names("Acessórios", "Accessories", "Accesorios"),
        "shopping.gifts": names("Presentes", "Gifts", "Regalos"),
        "pets": names("Pets", "Pets", "Mascotas"),
        "pets.food": names("Ração", "Pet food", "Alimento"),
        "pets.vet": names("Veterinário", "Veterinarian", "Veterinario"),
        "pets.grooming": names("Banho / Tosa", "Grooming", "Baño / Peluquería"),
        "pets.store": names("Pet Shop", "Pet store", "Tienda de mascotas"),
        "personalCare": names("Cuidados Pessoais", "Personal Care", "Cuidado personal"),
        "personalCare.hairBeauty": names("Cabelo / Beleza", "Hair / Beauty", "Cabello / Belleza"),
        "personalCare.hygiene": names("Higiene", "Hygiene", "Higiene"),
        "personalCare.cosmetics": names("Cosméticos", "Cosmetics", "Cosméticos"),
        "personalCare.professionals": names("Profissionais", "Professionals", "Profesionales"),
        "financial": names("Financeiro", "Financial", "Financiero"),
        "financial.interestFees": names("Juros / Taxas", "Interest / Fees", "Intereses / Cargos"),
        "financial.insurance": names("Seguros", "Insurance", "Seguros"),
        "financial.bankFees": names("Tarifas", "Bank fees", "Comisiones"),
        "financial.loan": names("Empréstimo", "Loan", "Préstamo"),
        "financial.taxes": names("Impostos", "Taxes", "Impuestos"),
        "subscriptions": names("Assinaturas", "Subscriptions", "Suscripciones"),
        "subscriptions.streaming": names("Streaming", "Streaming", "Streaming"),
        "subscriptions.music": names("Música", "Music", "Música"),
        "subscriptions.saas": names("SaaS", "SaaS", "SaaS"),
        "subscriptions.apps": names("Apps", "Apps", "Apps"),
        "subscriptions.cloudBackup": names("Cloud / Backup", "Cloud / Backup", "Nube / Respaldo"),
        "subscriptions.games": names("Jogos", "Games", "Juegos"),
        "sports": names("Esportes", "Sports", "Deportes"),
        "sports.gym": names("Academia", "Gym", "Gimnasio"),
        "sports.running": names("Corrida", "Running", "Running"),
        "sports.soccer": names("Futebol", "Soccer", "Fútbol"),
        "sports.tennis": names("Tênis", "Tennis", "Tenis"),
        "sports.cycling": names("Ciclismo", "Cycling", "Ciclismo"),
        "sports.swimming": names("Natação", "Swimming", "Natación"),
        "sports.general": names("Esportes em Geral", "General Sports", "Deportes en general"),
        "other": names("Outros", "Other", "Otros"),
        "other.gifts": names("Presentes", "Gifts", "Regalos"),
        "other.donations": names("Doações", "Donations", "Donaciones"),
        "other.misc": names("Outros", "Other", "Otros")
    ]
}
