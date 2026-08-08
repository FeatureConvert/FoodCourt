import Foundation

/// A rotating limited-time hire, independent of the festival/league seasons. No persisted
/// rotation state beyond a purchase marker - the pick itself is derived from the clock, the
/// same "compute it from `now`" approach `Festival`/`League` rollovers already use.
enum GuestChef {

    static let gemPrice = 400

    static func weekKey(now: Date, calendar: Calendar = .current) -> Int {
        let week = calendar.component(.weekOfYear, from: now)
        let year = calendar.component(.yearForWeekOfYear, from: now)
        return year * 100 + week
    }

    static func current(now: Date, calendar: Calendar = .current) -> ManagerSpec {
        let pool = ManagerCatalog.guestSpecs
        let key = weekKey(now: now, calendar: calendar)
        return pool[((key % pool.count) + pool.count) % pool.count]
    }
}
