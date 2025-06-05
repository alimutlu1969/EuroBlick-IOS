import SwiftUI

struct TestView: View {
    @State private var isShowingSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                Text("Test View")
                    .font(.headline)
                Button("Open Sheet") {
                    isShowingSheet = true
                }
                .sheet(isPresented: $isShowingSheet) {
                    VStack {
                        HStack {
                            Text("Sheet Title")
                                .foregroundColor(.white)
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                isShowingSheet = false
                            }) {
                                Text("Close")
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        Text("Sheet Content")
                            .foregroundColor(.white)
                    }
                    .background(Color.black)
                }
            }
        }
    }
}

#Preview {
    TestView()
}
