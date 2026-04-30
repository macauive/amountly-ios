//
//  Contact.swift
//  alpha
//
//  Created by Claude Code on 12/17/25.
//

import Foundation

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let organizationId: String?
    let userId: String?
    var name: String
    var email: String?
    var phone: String?
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var country: String?
    var contactName: String?
    var notes: String?
    var isActive: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case userId = "user_id"
        case name
        case email
        case phone
        case address
        case city
        case state
        case zipCode = "zip_code"
        case country
        case contactName = "contact_name"
        case notes
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        organizationId: String?,
        userId: String?,
        name: String,
        email: String?,
        phone: String?,
        address: String?,
        city: String?,
        state: String?,
        zipCode: String?,
        country: String?,
        contactName: String?,
        notes: String?,
        isActive: Bool,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.organizationId = organizationId
        self.userId = userId
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
        self.contactName = contactName
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zipCode = try container.decodeIfPresent(String.self, forKey: .zipCode)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = Self.decodeDateIfPresent(from: container, forKey: .createdAt)
        updatedAt = Self.decodeDateIfPresent(from: container, forKey: .updatedAt)
    }

    var displayName: String {
        name
    }

    var fullAddress: String {
        var components: [String] = []

        if let address = address, !address.isEmpty {
            components.append(address)
        }
        if let city = city, !city.isEmpty {
            components.append(city)
        }
        if let state = state, !state.isEmpty {
            components.append(state)
        }
        if let zipCode = zipCode, !zipCode.isEmpty {
            components.append(zipCode)
        }

        return components.joined(separator: ", ")
    }

    private static func decodeDateIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Create/Update DTOs

struct ContactCreate: Codable {
    var name: String
    var email: String?
    var phone: String?
    var address: String?
    var city: String?
    var state: String?
    var zipCode: String?
    var country: String?
    var contactName: String?
    var notes: String?
    var isActive: Bool = true

    enum CodingKeys: String, CodingKey {
        case name, email, phone, address, city, state, country, notes
        case zipCode = "zip_code"
        case contactName = "contact_name"
        case isActive = "is_active"
    }
}

// MARK: - Preview Data

extension Contact {
    static let preview = Contact(
        id: "preview-1",
        organizationId: "org-1",
        userId: nil,
        name: "Acme Corporation",
        email: "contact@acme.com",
        phone: "+1 555-0100",
        address: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zipCode: "94102",
        country: "USA",
        contactName: "John Smith",
        notes: "Primary client",
        isActive: true,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let previewList: [Contact] = [
        Contact(
            id: "1",
            organizationId: "org-1",
            userId: nil,
            name: "Acme Corporation",
            email: "contact@acme.com",
            phone: "+1 555-0100",
            address: "123 Main St",
            city: "San Francisco",
            state: "CA",
            zipCode: "94102",
            country: "USA",
            contactName: "John Smith",
            notes: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        Contact(
            id: "2",
            organizationId: "org-1",
            userId: nil,
            name: "TechCorp Inc",
            email: "info@techcorp.com",
            phone: "+1 555-0200",
            address: "456 Tech Blvd",
            city: "Austin",
            state: "TX",
            zipCode: "78701",
            country: "USA",
            contactName: "Jane Doe",
            notes: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        Contact(
            id: "3",
            organizationId: "org-1",
            userId: nil,
            name: "Global Industries",
            email: "hello@global.com",
            phone: "+1 555-0300",
            address: nil,
            city: "New York",
            state: "NY",
            zipCode: "10001",
            country: "USA",
            contactName: nil,
            notes: "Vendor for office supplies",
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}
