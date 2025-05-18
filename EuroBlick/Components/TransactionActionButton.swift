import SwiftUI

struct TransactionActionButton: View {
    let action: () -> Void
    var icon: String? = nil
    var systemIcon: String? = nil
    let label: String
    let color: Color
    var isProminent: Bool = false
    var accessibilityLabel: String
    var bounceEffect: Bool = false
    
    @State private var isPressed = false
    @State private var isBouncing = false
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: isProminent ? .medium : .light)
            generator.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 4) {
                if let icon = icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: isProminent ? 28 : 22, height: isProminent ? 28 : 22)
                } else if let systemIcon = systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: isProminent ? 24 : 20))
                        .foregroundColor(color)
                }
                
                Text(label)
                    .font(.system(size: isProminent ? 13 : 12))
                    .foregroundColor(color)
            }
            .padding(.vertical, 8)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .scaleEffect(bounceEffect && isBouncing ? 1.05 : 1.0)
            .animation(bounceEffect ? .spring(response: 0.5, dampingFraction: 0.6).repeatForever(autoreverses: true) : .none, value: isBouncing)
        }
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            if bounceEffect {
                withAnimation {
                    isBouncing = true
                }
            }
        }
    }
} 