/// Estonian public holidays (riigipühad) under the Public Holidays and Days of National Importance Act.
public enum EstonianHoliday: String, CaseIterable, Sendable {
    case newYearsDay
    case independenceDay
    case goodFriday
    case easterSunday
    case springDay
    case pentecost
    case victoryDay
    case midsummerDay
    case restorationOfIndependenceDay
    case christmasEve
    case christmasDay
    case boxingDay

    public var name: String {
        switch self {
        case .newYearsDay: "New Year's Day"
        case .independenceDay: "Independence Day"
        case .goodFriday: "Good Friday"
        case .easterSunday: "Easter Sunday"
        case .springDay: "Spring Day"
        case .pentecost: "Pentecost"
        case .victoryDay: "Victory Day"
        case .midsummerDay: "Midsummer Day"
        case .restorationOfIndependenceDay: "Day of Restoration of Independence"
        case .christmasEve: "Christmas Eve"
        case .christmasDay: "Christmas Day"
        case .boxingDay: "Boxing Day"
        }
    }

    public var estonianName: String {
        switch self {
        case .newYearsDay: "uusaasta"
        case .independenceDay: "iseseisvuspäev"
        case .goodFriday: "suur reede"
        case .easterSunday: "ülestõusmispühade 1. püha"
        case .springDay: "kevadpüha"
        case .pentecost: "nelipühade 1. püha"
        case .victoryDay: "võidupüha"
        case .midsummerDay: "jaanipäev"
        case .restorationOfIndependenceDay: "taasiseseisvumispäev"
        case .christmasEve: "jõululaupäev"
        case .christmasDay: "esimene jõulupüha"
        case .boxingDay: "teine jõulupüha"
        }
    }

    /// Employment Contracts Act § 53: working time is shortened by three hours on the
    /// working day preceding these holidays.
    public var shortensPrecedingDay: Bool {
        switch self {
        case .newYearsDay, .independenceDay, .victoryDay, .christmasEve: true
        default: false
        }
    }

    public static func holiday(on date: LocalDate) -> EstonianHoliday? {
        switch (date.month, date.day) {
        case (1, 1): return .newYearsDay
        case (2, 24): return .independenceDay
        case (5, 1): return .springDay
        case (6, 23): return .victoryDay
        case (6, 24): return .midsummerDay
        case (8, 20): return .restorationOfIndependenceDay
        case (12, 24): return .christmasEve
        case (12, 25): return .christmasDay
        case (12, 26): return .boxingDay
        default: break
        }
        let easter = easterSunday(year: date.year)
        switch easter.days(until: date) {
        case -2: return .goodFriday
        case 0: return .easterSunday
        case 49: return .pentecost
        default: return nil
        }
    }

    /// The holiday whose preceding-day reduction falls on `date`, if any.
    ///
    /// Only the calendar day directly before the holiday is affected. When that day is not a
    /// working day for the person, nothing is shortened and the reduction does not move to an
    /// earlier day. This follows the Labour Inspectorate's reading of § 53.
    public static func shortenedDay(on date: LocalDate) -> EstonianHoliday? {
        guard let next = holiday(on: date.adding(days: 1)), next.shortensPrecedingDay else { return nil }
        return next
    }

    public static func holidays(in year: Int) -> [(date: LocalDate, holiday: EstonianHoliday)] {
        LocalDate(year: year, month: 1, day: 1).through(LocalDate(year: year, month: 12, day: 31))
            .compactMap { date in holiday(on: date).map { (date, $0) } }
    }

    /// Western (Gregorian) Easter Sunday, using the anonymous Gregorian algorithm.
    public static func easterSunday(year: Int) -> LocalDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return LocalDate(year: year, month: month, day: day)
    }
}
