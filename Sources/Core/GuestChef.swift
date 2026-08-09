import Foundation

/// A rotating limited-time hire, independent of the festival/league seasons. No persisted
/// rotation state beyond a purchase marker - the pick itself is derived from the clock, the
/// same "compute it from `now`" approach `Festival`/`League` rollovers already use.
enum GuestChef {

    /// 700, up from 400: at 400 this was a guaranteed legendary for ~\$3-4 of gems while
    /// the Legendary Chef Crate charges \$9.99 cash for the same headline outcome - the
    /// gem route should be the patient path, not a 60% discount. Also separates the three
    /// once-identical 400-gem sinks (Star Infusion 250 / Automate Venue 400 / this at 700)
    /// so price signals value.
    static let gemPrice = 700

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
