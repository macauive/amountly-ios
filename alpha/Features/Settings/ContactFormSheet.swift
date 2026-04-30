//
//  ContactFormSheet.swift
//  alpha
//
//  Created by Claude Code on 12/17/25.
//

import SwiftUI

struct ContactFormSheet: View {
    @Binding var isPresented: Bool
    var contact: Contact?
    var onSave: () -> Void

    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var zipCode: String
    @State private var country: String
    @State private var contactName: String
    @State private var notes: String
    @State private var smartContactText = ""
    @State private var smartContactSummary: String?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let clientRepository = ClientRepository()

    init(isPresented: Binding<Bool>, contact: Contact? = nil, onSave: @escaping () -> Void) {
        self._isPresented = isPresented
        self.contact = contact
        self.onSave = onSave

        // Initialize state from contact if editing
        _name = State(initialValue: contact?.name ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _address = State(initialValue: contact?.address ?? "")
        _city = State(initialValue: contact?.city ?? "")
        _state = State(initialValue: contact?.state ?? "")
        _zipCode = State(initialValue: contact?.zipCode ?? "")
        _country = State(initialValue: contact?.country ?? "")
        _contactName = State(initialValue: contact?.contactName ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if contact == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.alphaPrimary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.alphaPrimary.opacity(0.1))
                                    .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Smart contact capture")
                                        .font(.alphaBodyMedium)
                                        .foregroundColor(.alphaPrimaryText)

                                    Text("Paste a client signature or contact block and Alpha will fill what it can.")
                                        .font(.alphaBodySmall)
                                        .foregroundColor(.alphaSecondaryText)
                                }
                            }

                            TextEditor(text: $smartContactText)
                                .frame(minHeight: 96)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.alphaBorder.opacity(0.5), lineWidth: 1)
                                )
                                .accessibilityLabel("Smart contact text")

                            HStack(alignment: .top, spacing: 12) {
                                Text(smartContactSummary ?? "Alpha looks for company, contact, email, phone, and address.")
                                    .font(.alphaCaption)
                                    .foregroundColor(.alphaSecondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    fillFromSmartContact()
                                } label: {
                                    Label("Fill client", systemImage: "wand.and.stars")
                                }
                                .font(.alphaCaption)
                                .disabled(smartContactText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Company Information") {
                    TextField("Company Name", text: $name)

                    TextField("Contact Person", text: $contactName)
                }

                Section("Contact Details") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("Address") {
                    TextField("Street Address", text: $address)

                    TextField("City", text: $city)

                    HStack {
                        TextField("State", text: $state)

                        TextField("ZIP Code", text: $zipCode)
                            .keyboardType(.numbersAndPunctuation)
                    }

                    TextField("Country", text: $country)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.alphaBodySmall)
                            .foregroundColor(.alphaError)
                    }
                }
            }
            .navigationTitle(contact == nil ? "Add Client" : "Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(contact == nil ? "Add" : "Save") {
                        Task {
                            await saveContact()
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                }
            }
        }
    }

    private func fillFromSmartContact() {
        let result = ContactCaptureParser.capture(from: smartContactText)

        if let capturedName = result.name, name.isEmpty {
            name = capturedName
        }
        if let capturedContactName = result.contactName, contactName.isEmpty {
            contactName = capturedContactName
        }
        if let capturedEmail = result.email, email.isEmpty {
            email = capturedEmail
        }
        if let capturedPhone = result.phone, phone.isEmpty {
            phone = capturedPhone
        }
        if let capturedAddress = result.address, address.isEmpty {
            address = capturedAddress
        }
        if let capturedCity = result.city, city.isEmpty {
            city = capturedCity
        }
        if let capturedState = result.state, state.isEmpty {
            state = capturedState
        }
        if let capturedZipCode = result.zipCode, zipCode.isEmpty {
            zipCode = capturedZipCode
        }
        if notes.isEmpty {
            notes = result.notes ?? ""
        }

        smartContactSummary = result.reason
    }

    private func saveContact() async {
        isSaving = true
        errorMessage = nil

        do {
            if let existingContact = contact {
                // Update existing contact
                _ = try await clientRepository.updateClient(
                    id: existingContact.id,
                    name: name,
                    email: email.isEmpty ? nil : email,
                    phone: phone.isEmpty ? nil : phone,
                    address: address.isEmpty ? nil : address,
                    city: city.isEmpty ? nil : city,
                    state: state.isEmpty ? nil : state,
                    zipCode: zipCode.isEmpty ? nil : zipCode,
                    country: country.isEmpty ? nil : country,
                    contactName: contactName.isEmpty ? nil : contactName,
                    notes: notes.isEmpty ? nil : notes
                )
            } else {
                // Create new contact
                _ = try await clientRepository.createClient(
                    name: name,
                    email: email.isEmpty ? nil : email,
                    phone: phone.isEmpty ? nil : phone,
                    address: address.isEmpty ? nil : address,
                    city: city.isEmpty ? nil : city,
                    state: state.isEmpty ? nil : state,
                    zipCode: zipCode.isEmpty ? nil : zipCode,
                    country: country.isEmpty ? nil : country,
                    contactName: contactName.isEmpty ? nil : contactName,
                    notes: notes.isEmpty ? nil : notes
                )
            }

            onSave()
            isPresented = false
        } catch {
            errorMessage = "Failed to save contact: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

private struct ContactCaptureResult {
    var name: String?
    var contactName: String?
    var email: String?
    var phone: String?
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var notes: String?
    var reason: String
}

private enum ContactCaptureParser {
    nonisolated static func capture(from text: String) -> ContactCaptureResult {
        let email = firstMatch(in: text, pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive])
        let phone = firstMatch(in: text, pattern: #"(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}"#)
        let addressPattern = #"\b\d{1,6}[ \t]+[A-Za-z0-9 .'-]+(?:street|st|avenue|ave|road|rd|drive|dr|lane|ln|boulevard|blvd|way|court|ct)\b"#
        let address = firstMatch(in: text, pattern: addressPattern, options: [.caseInsensitive])
        let cityStateZip = captureGroups(in: text, pattern: #"\b([A-Za-z .'-]+),\s*([A-Z]{2})\s+(\d{5}(?:-\d{4})?)\b"#)

        let lines = text
            .components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map(cleanupLine)
            .filter { !$0.isEmpty }

        let ignored = [email, phone, address, cityStateZip.first].compactMap { $0 }
        let candidateLines = lines.filter { line in
            !ignored.contains(where: { line.contains($0) }) &&
            firstMatch(in: line, pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, options: [.caseInsensitive]) == nil &&
            firstMatch(in: line, pattern: #"(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}"#) == nil &&
            firstMatch(in: line, pattern: addressPattern, options: [.caseInsensitive]) == nil
        }

        let companyLine = lines.first(where: { hasPrefixLabel($0, labels: ["company", "client"]) }) ?? candidateLines.first
        let contactLine = lines.first(where: { hasPrefixLabel($0, labels: ["contact", "name"]) }) ??
            candidateLines.first(where: { $0 != companyLine && $0.split(separator: " ").count <= 4 })

        return ContactCaptureResult(
            name: companyLine.map(titleCase),
            contactName: contactLine.map(titleCase),
            email: email,
            phone: phone,
            address: address,
            city: value(in: cityStateZip, at: 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
            state: value(in: cityStateZip, at: 2),
            zipCode: value(in: cityStateZip, at: 3),
            notes: text.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: "Alpha looked for company, contact, email, phone, and address details."
        )
    }

    nonisolated private static func cleanupLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^company\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^client\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^contact\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^name\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func titleCase(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }

    nonisolated private static func hasPrefixLabel(_ line: String, labels: [String]) -> Bool {
        labels.contains { label in
            line.range(of: #"^\#(label)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    nonisolated private static func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    nonisolated private static func captureGroups(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return [] }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[groupRange])
        }
    }

    nonisolated private static func value(in values: [String], at index: Int) -> String? {
        values.indices.contains(index) ? values[index] : nil
    }
}

// MARK: - Preview

#Preview("New Contact") {
    ContactFormSheet(isPresented: .constant(true), onSave: {})
}

#Preview("Edit Contact") {
    ContactFormSheet(isPresented: .constant(true), contact: .preview, onSave: {})
}
