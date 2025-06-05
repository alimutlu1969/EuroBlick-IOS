import SwiftUI
import MessageUI

struct FeedbackSheetView: View {
    @State private var feedbackText: String = ""
    @State private var showMailView = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    @State private var showMailError = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wir freuen uns über Ihr Feedback!")
                    .font(.headline)
                TextEditor(text: $feedbackText)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                Spacer()
                Button(action: {
                    if MFMailComposeViewController.canSendMail() {
                        showMailView = true
                    } else {
                        showMailError = true
                    }
                }) {
                    HStack {
                        Spacer()
                        Text("Absenden")
                            .bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Feedback senden")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showMailView) {
                MailView(isShowing: $showMailView, result: $mailResult, feedbackText: feedbackText)
            }
            .alert("Mail kann nicht gesendet werden", isPresented: $showMailError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Bitte richte einen Mail-Account auf deinem Gerät ein.")
            }
        }
    }
}

struct MailView: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    @Binding var result: Result<MFMailComposeResult, Error>?
    var feedbackText: String
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var isShowing: Bool
        @Binding var result: Result<MFMailComposeResult, Error>?
        
        init(isShowing: Binding<Bool>, result: Binding<Result<MFMailComposeResult, Error>?>) {
            _isShowing = isShowing
            _result = result
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            defer { isShowing = false }
            if let error = error {
                self.result = .failure(error)
            } else {
                self.result = .success(result)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(isShowing: $isShowing, result: $result)
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(["ali.mutlu@me.com"])
        vc.setSubject("EuroBlick Feedback")
        vc.setMessageBody(feedbackText, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
} 