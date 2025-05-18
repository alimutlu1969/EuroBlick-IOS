import SwiftUI

struct ActionButton: View {
    let title: String
    let backgroundColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(backgroundColor)
                .cornerRadius(12)
                .font(.system(size: 17, weight: .medium))
        }
    }
} 