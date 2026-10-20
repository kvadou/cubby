import Foundation

// Shapes returned by the Rails API's family endpoints (api/app/controllers/api/v1/parent).

/// A calendar date with no time or zone ("2026-10-19"), such as an attendance day or a due date.
struct CalendarDay: Codable, Hashable, Sendable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(raw)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    /// Noon in the Gregorian calendar, so formatting in any zone shows the same day.
    var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct Me: Codable, Sendable {
    struct User: Codable, Sendable {
        let id: Int
        let name: String
        let emailAddress: String
    }

    struct FamilyRef: Codable, Sendable, Hashable {
        let id: Int
        let name: String
        let centerName: String
    }

    let user: User
    let families: [FamilyRef]
}

struct TokenResponse: Codable, Sendable {
    let token: String
    let user: Me.User
    let families: [Me.FamilyRef]
}

struct FamilyHome: Codable, Sendable {
    struct Family: Codable, Sendable {
        let id: Int
        let name: String
        let guardianName: String
    }

    struct Center: Codable, Sendable {
        let name: String
        let city: String
        let timezone: String
        let directorName: String
    }

    struct Child: Codable, Sendable, Identifiable {
        struct Day: Codable, Sendable {
            let checkedInAt: Date
            let checkedOutAt: Date?
        }

        let id: Int
        let firstName: String
        let classroom: String?
        let status: String?
        let today: Day?
    }

    let family: Family
    let center: Center
    let today: CalendarDay
    let unreadMessages: Int
    let children: [Child]
}

struct AttendanceDay: Codable, Sendable, Identifiable {
    let on: CalendarDay
    let classroom: String
    let checkedInAt: Date
    let checkedOutAt: Date?

    var id: CalendarDay { on }
}

struct FamilyMessage: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let subject: String
    let body: String
    let sentAt: Date
    let readAt: Date?
    let from: String

    var isUnread: Bool { readAt == nil }
}

struct Invoice: Codable, Sendable, Identifiable {
    let id: Int
    let number: String
    let amountCents: Int
    let periodStart: CalendarDay
    let periodEnd: CalendarDay
    let dueOn: CalendarDay
    let status: String
    let daysPastDue: Int
    let paidAt: Date?

    var isOpen: Bool { status == "open" }
    var isPastDue: Bool { isOpen && daysPastDue > 0 }
    var amount: Decimal { Decimal(amountCents) / 100 }
}

extension JSONDecoder {
    /// snake_case keys and ISO 8601 timestamps with an offset, as Rails renders them.
    static var cubby: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(raw, strategy: .iso8601) { return date }
            if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a timestamp: \(raw)"))
        }
        return decoder
    }
}
