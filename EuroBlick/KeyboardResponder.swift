import SwiftUI
import Combine

class KeyboardResponder: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Beobachte, wenn die Tastatur erscheint
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self?.keyboardHeight = keyboardFrame.height
                }
            }
            .store(in: &cancellables)
        
        // Beobachte, wenn die Tastatur verschwindet
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.keyboardHeight = 0
            }
            .store(in: &cancellables)
    }
}
