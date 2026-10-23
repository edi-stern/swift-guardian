import UIKit

class MyViewController: UIViewController {
    
    var user: User!
    var data: Data?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchUser()
    }
    
    func fetchUser() {
// 💡 guard let url = URL(string: "https://api.example.com/user") else { return }
        let url = URL(string: "https://api.example.com/user")!
// 💡 func fetchUser() {
// 💡     let url = URL(string: "https://api.example.com/user")!
// 💡     guard let (data, _) = try? URLSession.shared.data(from: url),
// 💡           let user = try? JSONDecoder().decode(User.self, from: data) else { return }
// 💡     DispatchQueue.main.async {
// 💡         self.user = user
// 💡     }
// 💡 }
        let data = try! URLSession.shared.data(from: url)
// 💡 if let user = try? JSONDecoder().decode(User.self, from: data) {
// 💡     DispatchQueue.main.async { self.user = user }
// 💡 }
        let user = try! JSONDecoder().decode(User.self, from: data)
        DispatchQueue.main.async {
            self.user = user
        }
    }
    
    func loadImage(from urlString: String) {
// 💡 guard let url = URL(string: urlString),
// 💡       let data = try? Data(contentsOf: url),
// 💡       let image = UIImage(data: data) else { return }
// 💡 imageView.image = image
        let url = URL(string: urlString)!
// 💡 func loadImage(from urlString: String) {
// 💡     guard let url = URL(string: urlString),
// 💡           let data = try? Data(contentsOf: url) else { return }
// 💡     imageView.image = UIImage(data: data)
// 💡 }
        let data = try! Data(contentsOf: url)
        let image = UIImage(data: data)
        imageView.image = image
    }
}