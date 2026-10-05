import SwiftUI

/// "AI Lookup" settings: the two API keys, a key test, today's count, and what is sent where.
struct AILookupSettingsView: View {
    @State private var braveKey = AIKeychain.key(for: .brave) ?? ""
    @State private var deepSeekKey = AIKeychain.key(for: .deepSeek) ?? ""
    @State private var braveResult: String?
    @State private var deepSeekResult: String?
    @State private var isTesting = false
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField("Brave Search API key", text: $braveKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("DeepSeek API key", text: $deepSeekKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save Keys", action: saveKeys)
            } header: {
                Text("API keys")
            } footer: {
                Text(savedMessage ?? "Keys are stored only in this iPhone's Keychain.")
            }

            Section("Check") {
                Button {
                    Task { await testKeys() }
                } label: {
                    if isTesting {
                        HStack { ProgressView(); Text("Testing…") }
                    } else {
                        Text("Test Keys")
                    }
                }
                .disabled(isTesting)
                if let braveResult {
                    LabeledContent("Brave Search", value: braveResult)
                }
                if let deepSeekResult {
                    LabeledContent("DeepSeek", value: deepSeekResult)
                }
            }

            Section("Today") {
                LabeledContent("Lookups used", value: "\(AILookupLimit.usedToday) of \(AILookupLimit.dailyCap)")
                LabeledContent("Remaining", value: "\(AILookupLimit.remainingToday)")
            }

            Section("What is sent where") {
                Text("Brave Search gets the food name you search for.")
                Text("DeepSeek gets the food name, the titles and addresses of the search results, and the text of the product page it reads.")
                Text("Photos you take or choose are read on this iPhone and are never uploaded.")
            }
            .font(.subheadline)
        }
        .navigationTitle("AI Lookup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveKeys() {
        let braveSaved = AIKeychain.setKey(braveKey, for: .brave)
        let deepSeekSaved = AIKeychain.setKey(deepSeekKey, for: .deepSeek)
        savedMessage = braveSaved && deepSeekSaved ? "Saved in this iPhone's Keychain." : "The Keychain couldn't save a key. Try again."
        braveResult = nil
        deepSeekResult = nil
    }

    private func testKeys() async {
        saveKeys()
        isTesting = true
        async let brave = AIKeyTester.test(.brave)
        async let deepSeek = AIKeyTester.test(.deepSeek)
        (braveResult, deepSeekResult) = await (brave, deepSeek)
        isTesting = false
    }
}
