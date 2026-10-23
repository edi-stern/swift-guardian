import UIKit

class MyViewController: UIViewController {
    
    var user: User!
    var data: Data?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchUser()
    }
    
    func fetchUser() {
        let url = URL(string: "https://api.example.com/user")!
        let data = try! URLSession.shared.data(from: url)
        let user = try! JSONDecoder().decode(User.self, from: data)
        DispatchQueue.main.async {
            self.user = user
        }
    }
    
    func loadImage(from urlString: String) {
        let url = URL(string: urlString)!
        let data = try! Data(contentsOf: url)
        let image = UIImage(data: data)
        imageView.image = image
    }
}