import Combine
import Foundation
import Supabase

struct GearCatalogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let category: ProfileGearCategory
    let brand: String
    let model: String
    let variants: [String]
    let isFeatured: Bool
    let sortOrder: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case brand
        case model
        case variants
        case isFeatured = "is_featured"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    var displayName: String {
        let cleanBrand = brand.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanModel = model.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if cleanModel
            .lowercased()
            .hasPrefix(cleanBrand.lowercased()) {
            return cleanModel
        }

        return "\(cleanBrand) \(cleanModel)"
    }
}

@MainActor
final class GearCatalogStore: ObservableObject {
    @Published private(set) var entries: [GearCatalogEntry] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var loadedCategories: Set<ProfileGearCategory> = []

    // Stable, app-bundled choices: available even when the remote catalog
    // is empty/offline. These IDs are local-only and MUST NOT be written into
    // the gear_details.catalog_item_id FK.
    private static let builtInHeadphones: [GearCatalogEntry] = {
        let products: [(String, String)] = [
            ("Apple", "AirPods Pro 2"),
            ("Apple", "AirPods 4"),
            ("Apple", "AirPods 4 with ANC"),
            ("Apple", "AirPods Max"),
            ("Beats", "Powerbeats Pro 2"),
            ("Beats", "Beats Fit Pro"),
            ("Beats", "Studio Pro"),
            ("Beats", "Solo 4"),
            ("Shokz", "OpenRun Pro 2"),
            ("Shokz", "OpenRun"),
            ("Shokz", "OpenFit 2"),
            ("Shokz", "OpenSwim Pro"),
            ("Sony", "WH-1000XM6"),
            ("Sony", "WH-1000XM5"),
            ("Sony", "WF-1000XM5"),
            ("Sony", "LinkBuds Fit"),
            ("Sony", "LinkBuds Open"),
            ("Sony", "ULT WEAR"),
            ("Sonos", "Ace"),
            ("Samsung", "Galaxy Buds3 Pro"),
            ("Samsung", "Galaxy Buds3"),
            ("Samsung", "Galaxy Buds2 Pro"),
            ("Samsung", "Galaxy Buds FE"),
            ("Bose", "QuietComfort Ultra Headphones"),
            ("Bose", "QuietComfort Ultra Earbuds"),
            ("Bose", "QuietComfort Headphones"),
            ("Sennheiser", "MOMENTUM 4 Wireless"),
            ("Sennheiser", "MOMENTUM True Wireless 4"),
            ("Sennheiser", "ACCENTUM Plus Wireless"),
            ("JBL", "Tour Pro 3"),
            ("JBL", "Live Pro 2 TWS"),
            ("JBL", "Endurance Peak 3"),
            ("JBL", "Tune 770NC"),
            ("Jabra", "Elite 8 Active Gen 2"),
            ("Jabra", "Elite 10 Gen 2"),
            ("Jabra", "Elite 7 Active"),
            ("Anker Soundcore", "Sport X20"),
            ("Anker Soundcore", "Liberty 4 NC"),
            ("Anker Soundcore", "AeroFit 2"),
            ("Anker Soundcore", "Space One"),
            ("Bowers & Wilkins", "Px8"),
            ("Bowers & Wilkins", "Px7 S2e"),
            ("Bowers & Wilkins", "Pi8"),
            ("Bang & Olufsen", "Beoplay H100"),
            ("Bang & Olufsen", "Beoplay EX"),
            ("Marshall", "Major V"),
            ("Marshall", "Monitor III A.N.C."),
            ("Marshall", "Motif II A.N.C."),
            ("Nothing", "Ear"),
            ("Nothing", "Ear (a)"),
            ("Nothing", "Headphone (1)"),
            ("Skullcandy", "Crusher ANC 2"),
            ("Skullcandy", "Rail ANC"),
            ("Google", "Pixel Buds Pro 2"),
            ("Google", "Pixel Buds A-Series"),
            ("Huawei", "FreeClip"),
            ("Huawei", "FreeBuds Pro 4"),
            ("OnePlus", "Buds Pro 3"),
            ("Technics", "EAH-AZ100"),
            ("Technics", "EAH-AZ80")
        ]
        let featured = Set([
            "AirPods Pro 2",
            "Powerbeats Pro 2",
            "OpenRun Pro 2",
            "WH-1000XM6",
            "Ace",
            "Galaxy Buds3 Pro",
            "QuietComfort Ultra Earbuds",
            "MOMENTUM 4 Wireless"
        ])
        return products.enumerated().compactMap { index, item in
            guard let id = UUID(
                uuidString: String(
                    format: "a7c00001-0000-4000-8000-%012x",
                    index + 1
                )
            ) else {
                return nil
            }

            return GearCatalogEntry(
                id: id,
                category: .headphones,
                brand: item.0,
                model: item.1,
                variants: [],
                isFeatured: featured.contains(item.1),
                sortOrder: 10_000 + index,
                isActive: true
            )
        }
    }()

    func isBuiltIn(_ item: GearCatalogEntry) -> Bool {
        Self.builtInHeadphones.contains { $0.id == item.id }
    }

    private func availableEntries(
        for category: ProfileGearCategory
    ) -> [GearCatalogEntry] {
        let remote = entries.filter {
            $0.category == category && $0.isActive
        }
        guard category == .headphones else {
            return remote
        }

        var seen: Set<String> = []
        return (remote + Self.builtInHeadphones).filter { item in
            let key = item.brand.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) + "|" + item.model.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            return seen.insert(key).inserted
        }
    }

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(
        category: ProfileGearCategory,
        force: Bool = false
    ) async {
        if loadedCategories.contains(category) && !force {
            return
        }

        guard client.auth.currentUser != nil else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [GearCatalogEntry] = try await client
                .from("gear_catalog")
                .select(
                    "id,category,brand,model,variants,is_featured,sort_order,is_active"
                )
                .eq("category", value: category.rawValue)
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .order("model", ascending: true)
                .execute()
                .value

            entries.removeAll { $0.category == category }
            entries.append(contentsOf: rows)
            loadedCategories.insert(category)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func brands(
        for category: ProfileGearCategory
    ) -> [String] {
        let rows = availableEntries(for: category)
            .sorted(by: catalogSort)

        var seen: Set<String> = []
        var result: [String] = []

        for row in rows {
            let key = row.brand.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }

            result.append(row.brand)
        }

        return result
    }

    func models(
        for category: ProfileGearCategory,
        brand: String
    ) -> [GearCatalogEntry] {
        availableEntries(for: category)
            .filter {
                $0.brand.compare(
                    brand,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
            }
            .sorted(by: catalogSort)
    }

    func featured(
        for category: ProfileGearCategory,
        brand: String? = nil,
        limit: Int = 6
    ) -> [GearCatalogEntry] {
        Array(
            availableEntries(for: category)
                .filter {
                    guard $0.isFeatured else {
                        return false
                    }

                    guard let brand,
                          !brand.isEmpty
                    else {
                        return true
                    }

                    return $0.brand.compare(
                        brand,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }
                .sorted(by: catalogSort)
                .prefix(limit)
        )
    }

    func entry(
        id: UUID?
    ) -> GearCatalogEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    func matchingEntry(
        category: ProfileGearCategory,
        brand: String,
        model: String
    ) -> GearCatalogEntry? {
        availableEntries(for: category).first {
            $0.brand.compare(
                brand,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame &&
            $0.model.compare(
                model,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    private func catalogSort(
        _ lhs: GearCatalogEntry,
        _ rhs: GearCatalogEntry
    ) -> Bool {
        if lhs.isFeatured != rhs.isFeatured {
            return lhs.isFeatured && !rhs.isFeatured
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        if lhs.brand != rhs.brand {
            return lhs.brand.localizedCaseInsensitiveCompare(rhs.brand)
                == .orderedAscending
        }

        return lhs.model.localizedCaseInsensitiveCompare(rhs.model)
            == .orderedAscending
    }
}
