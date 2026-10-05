import SwiftUI

/// "AI Lookup" settings: the two API keys, a key test, today's count, and what is sent where.
struct AILookupSettingsView: View {
    @State private var braveKey = AIKeychain.key(for: .brave) ?? ""
    @State private var deepSeekKey = AIKeychain.key(for: .deepSeek) ?? ""
    @State private var showsKeys = false
    @State private var braveResult: KeyTestResult?
    @State private var deepSeekResult: KeyTestResult?
    /// Whether the last test used keys that differ from the saved ones.
    @State private var testedUnsavedKeys = false
    @State private var savedMessage: String?
    @State private var hasSavedBrave = AIKeychain.hasKey(for: .brave)
    @State private var hasSavedDeepSeek = AIKeychain.hasKey(for: .deepSeek)

    var body: some View {
        Form {
            Section {
                keyField("Brave Search API key", text: $braveKey)
                keyField("DeepSeek API key", text: $deepSeekKey)
                Toggle("Show keys", isOn: $showsKeys)
                Button("Save Keys", action: saveKeys)
            } header: {
                Text("API keys")
            } footer: {
                Text(savedMessage ?? "Keys are stored only in this iPhone's Keychain. An empty box never erases a saved key.")
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
                     ? "Tested the keys in the boxes above. They aren't saved yet — tap Save Keys."
                     : "Tests the keys in the boxes above.")
            }

            if hasSavedBrave || hasSavedDeepSeek {
                Section("Remove a saved key") {
                    if hasSavedBrave {
                        Button("Remove Brave Search Key", role: .destructive) { remove(.brave) }
                    }
                    if hasSavedDeepSeek {
                        Button("Remove DeepSeek Key", role: .destructive) { remove(.deepSeek) }
                    }
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

    @State private var isTesting = false

    /// A key box. Not marked as a password box, so iOS doesn't offer to fill in saved passwords.
    @ViewBuilder
    private func keyField(_ title: String, text: Binding<String>) -> some View {
        Group {
            if showsKeys {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .privacySensitive()
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

    /// Saves both boxes. Refuses a box that clearly holds the other service's key, and the same
    /// key in both boxes; an empty box keeps the saved key.
    private func saveKeys() {
        braveKey = AIKeychain.normalize(braveKey)
        deepSeekKey = AIKeychain.normalize(deepSeekKey)
        braveResult = nil
        deepSeekResult = nil
        testedUnsavedKeys = false

        if !braveKey.isEmpty && braveKey == deepSeekKey {
            savedMessage = "Both boxes hold the same key. Paste the Brave Search key and the DeepSeek key into their own boxes."
            return
        }
        var messages: [String] = []
        for (service, value) in [(AIService.brave, braveKey), (.deepSeek, deepSeekKey)] {
            if let warning = AIKeychain.wrongServiceWarning(value, for: service) {
                messages.append("\(warning) Not saved.")
                continue
            }
            switch AIKeychain.setKey(value, for: service) {
            case .saved:
                messages.append("\(service.rawValue) key saved.")
                // A new Brave key may include image search even if the old one didn't.
                if service == .brave { ImageSearchAvailability.reset() }
            case .unchanged: break
            case .keptExistingBecauseEmpty:
                if AIKeychain.hasKey(for: service) {
                    messages.append("\(service.rawValue) box was empty, so the saved key was kept.")
                    if service == .brave { braveKey = AIKeychain.key(for: .brave) ?? "" }
                    if service == .deepSeek { deepSeekKey = AIKeychain.key(for: .deepSeek) ?? "" }
                }
            case .failed: messages.append("The Keychain couldn't save the \(service.rawValue) key. Try again.")
            }
        }
        hasSavedBrave = AIKeychain.hasKey(for: .brave)
        hasSavedDeepSeek = AIKeychain.hasKey(for: .deepSeek)
        savedMessage = messages.isEmpty ? "No changes to save." : messages.joined(separator: " ")
    }

    private func remove(_ service: AIService) {
        AIKeychain.removeKey(for: service)
        if service == .brave { braveKey = ""; braveResult = nil }
        if service == .deepSeek { deepSeekKey = ""; deepSeekResult = nil }
        hasSavedBrave = AIKeychain.hasKey(for: .brave)
        hasSavedDeepSeek = AIKeychain.hasKey(for: .deepSeek)
        savedMessage = "\(service.rawValue) key removed."
    }

    /// Tests exactly what's in the boxes, saved or not.
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
