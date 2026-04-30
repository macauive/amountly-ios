//
//  ContactsListView.swift
//  alpha
//
//  Created by Claude Code on 12/17/25.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    var filteredContacts: [Contact] {
        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return contacts }

        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(normalized) ||
            (contact.contactName?.localizedCaseInsensitiveContains(normalized) ?? false) ||
            (contact.email?.localizedCaseInsensitiveContains(normalized) ?? false) ||
            (contact.phone?.localizedCaseInsensitiveContains(normalized) ?? false)
        }
    }

    private let clientRepository = ClientRepository()

    // MARK: - Public Methods

    func loadContacts() async {
        isLoading = true
        errorMessage = nil

        do {
            contacts = try await clientRepository.fetchClients(activeOnly: false)
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            contacts = []
        }

        isLoading = false
    }

    func deleteContact(_ contactId: String) async {
        do {
            try await clientRepository.deleteClient(id: contactId)
            await loadContacts()
        } catch {
            errorMessage = "Failed to delete contact: \(error.localizedDescription)"
        }
    }
}

// MARK: - ContactsListView

struct ContactsListView: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var showingAddContact = false
    @State private var selectedContact: Contact?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if let error = viewModel.errorMessage {
                        errorState(error)
                    } else if viewModel.contacts.isEmpty {
                        emptyState
                    } else if viewModel.filteredContacts.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else {
                        HStack {
                            Label("All Clients (\(viewModel.contacts.count))", systemImage: "person.2.fill")
                                .font(.alphaHeadlineSmall)
                                .foregroundColor(.alphaPrimaryText)

                            Spacer()
                        }
                        .padding(.horizontal)

                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.filteredContacts) { contact in
                                ContactRow(contact: contact)
                                    .onTapGesture {
                                        selectedContact = contact
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteContact(contact.id)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.alphaGroupedBackground)
            .navigationTitle("Clients")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search clients")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddContact = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.alphaPrimary)
                    }
                }
            }
            .refreshable {
                await viewModel.loadContacts()
            }
            .task {
                await viewModel.loadContacts()
            }
            .sheet(isPresented: $showingAddContact) {
                ContactFormSheet(isPresented: $showingAddContact, onSave: {
                    Task {
                        await viewModel.loadContacts()
                    }
                })
                .withAppTheme()
            }
            .sheet(item: $selectedContact) { contact in
                ContactFormSheet(isPresented: Binding(
                    get: { selectedContact != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedContact = nil
                        }
                    }
                ), contact: contact, onSave: {
                    Task {
                        await viewModel.loadContacts()
                        selectedContact = nil
                    }
                })
                .withAppTheme()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(.alphaSecondaryText)

            Text("No contacts yet")
                .font(.alphaBody)
                .foregroundColor(.alphaSecondaryText)

            Text("Tap + to add your first contact")
                .font(.alphaBodySmall)
                .foregroundColor(.alphaTertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(.alphaError.opacity(0.8))

            Text("Error loading clients")
                .font(.alphaBody)
                .fontWeight(.semibold)
                .foregroundColor(.alphaPrimaryText)

            Text(error)
                .font(.alphaBodySmall)
                .foregroundColor(.alphaSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task {
                    await viewModel.loadContacts()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Initials circle
                Circle()
                    .fill(Color.alphaPrimary.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.alphaPrimary)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.alphaPrimaryText)

                    if let contactName = contact.contactName {
                        Text(contactName)
                            .font(.system(size: 14))
                            .foregroundColor(.alphaSecondaryText)
                    }
                }

                Spacer()

                Text(contact.isActive ? "Active" : "Inactive")
                    .font(.alphaCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(contact.isActive ? .alphaSuccess : .alphaSecondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((contact.isActive ? Color.alphaSuccess : Color.alphaSecondaryText).opacity(0.12))
                    .cornerRadius(8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.alphaSecondaryText)
            }

            if contact.email != nil || contact.phone != nil {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    if let email = contact.email {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.alphaSecondaryText)
                                .frame(width: 16)

                            Text(email)
                                .font(.system(size: 13))
                                .foregroundColor(.alphaSecondaryText)
                        }
                    }

                    if let phone = contact.phone {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.alphaSecondaryText)
                                .frame(width: 16)

                            Text(phone)
                                .font(.system(size: 13))
                                .foregroundColor(.alphaSecondaryText)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.alphaCardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var initials: String {
        let components = contact.name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Preview

#Preview("Contacts List") {
    ContactsListView()
}

#Preview("Contact Row") {
    ContactRow(contact: .preview)
        .padding()
}
