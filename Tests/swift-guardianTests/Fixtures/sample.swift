import Foundation

func fetchUser() {
    let name: String? = nil
    let unwrapped = name!
    let safe = name ?? "default"
    let data = try! Data(contentsOf: URL(string: "https://example.com")!)
    let safeTry = try? JSONDecoder().decode(String.self, from: Data())
}
