import Foundation

func fetchUser() {
    let name: String? = nil
    let _ = name!
    let _ = name ?? "default"
    let _ = try! Data(contentsOf: URL(string: "https://example.com")!)
    let _ = try? JSONDecoder().decode(String.self, from: Data())
}
