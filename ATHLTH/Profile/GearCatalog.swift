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
        let rows = entries
            .filter {
                $0.category == category &&
                $0.isActive
            }
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
        entries
            .filter {
                $0.category == category &&
                $0.brand.compare(
                    brand,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame &&
                $0.isActive
            }
            .sorted(by: catalogSort)
    }

    func featured(
        for category: ProfileGearCategory,
        brand: String? = nil,
        limit: Int = 6
    ) -> [GearCatalogEntry] {
        Array(
            entries
                .filter {
                    guard $0.category == category,
                          $0.isActive,
                          $0.isFeatured
                    else {
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
        entries.first {
            $0.category == category &&
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
