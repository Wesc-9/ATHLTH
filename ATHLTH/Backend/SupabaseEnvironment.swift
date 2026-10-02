import Foundation
import Supabase

enum SupabaseEnvironment {
    static let projectURL = URL(string: "https://hnkybbzxffvyhzrstqdo.supabase.co")!
    static let publishableKey = "sb_publishable_rBJpdMowyqt7A25eRd32dg_x7Szon8p"

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: publishableKey
    )
}
