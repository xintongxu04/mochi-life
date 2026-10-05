import SwiftUI

/// "AI Lookup" settings: the two API keys, a key test, today's count, and what is sent where.
struct AILookupSettingsView: View {
    @State private var braveKey = AIKeychain.key(for: .brave) ?? ""
    @State private var deepSeekKey = AIKeychain.key(for: .deepSeek) ?? ""
    @State private var braveResult: KeyTestResult?
    @State private var deepSeekResult: KeyTestResult?
    /// The fields' values that were tested, and whether they matched what's saved.
    @State private var testedUnsavedKeys = false
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

            Section {
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
                    resultRow("Brave Search", braveResult)
                }
                if let deepSeekResult {
                    resultRow("DeepSeek", deepSeekResult)
                }
            } footer: {
                Text(testedUnsavedKeys
                     ? "Tested the keys in the fields above. They aren't saved yet — tap Save Keys."
                     : "Tests the keys in the fields above.")
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

    private func resultRow(_ service: String, _ result: KeyTestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(service, value: result.summary)
            if let message = result.serviceMessage {
                Text("\(service) says: \(message)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let hint = result.keyHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func saveKeys() {
        braveKey = AIKeychain.normalize(braveKey)
        deepSeekKey = AIKeychain.normalize(deepSeekKey)
        testedUnsavedKeys = false
        let braveSaved = AIKeychain.setKey(braveKey, for: .brave)
        let deepSeekSaved = AIKeychain.setKey(deepSeekKey, for: .deepSeek)
        savedMessage = braveSaved && deepSeekSaved ? "Saved in this iPhone's Keychain." : "The Keychain couldn't save a key. Try again."
        braveResult = nil
        deepSeekResult = nil
    }

    /// Tests exactly what's in the fields, saved or not.
    private func testKeys() async {
        testedUnsavedKeys = AIKeychain.normalize(braveKey) != (AIKeychain.key(for: .brave) ?? "")
            || AIKeychain.normalize(deepSeekKey) != (AIKeychain.key(for: .deepSeek) ?? "")
        isTesting = true
        async let brave = AIKeyTester.test(.brave, key: braveKey)
        async let deepSeek = AIKeyTester.test(.deepSeek, key: deepSeekKey)
        (braveResult, deepSeekResult) = await (brave, deepSeek)
        isTesting = false
    }
}
