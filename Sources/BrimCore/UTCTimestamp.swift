import Foundation

/// Parses the one timestamp shape session transcripts are written in:
/// `YYYY-MM-DDTHH:MM:SS`, optionally followed by a fraction, in UTC.
///
/// Written by hand because of the volume. The transcripts on a working Mac run to
/// gigabytes and hold hundreds of thousands of these, and a general-purpose date
/// parser is orders of magnitude too slow to be pointed at them: this is the
/// difference between a view that opens and one that beachballs.
///
/// Anything that is not exactly this shape is refused rather than guessed at. A
/// stamp carrying a local-time offset is not read as if it were UTC, because a
/// timestamp silently wrong by hours would put work on the wrong day.
public enum UTCTimestamp {
    public static func parse(_ bytes: some RandomAccessCollection<UInt8>) -> Date? {
        guard bytes.count >= 19 else { return nil }
        let base = bytes.startIndex
        func byte(_ offset: Int) -> UInt8 { bytes[bytes.index(base, offsetBy: offset)] }
        func number(_ offset: Int, _ length: Int) -> Int? {
            var total = 0
            for step in 0..<length {
                let digit = Int(byte(offset + step)) - 48
                guard (0...9).contains(digit) else { return nil }
                total = total * 10 + digit
            }
            return total
        }
        guard let year = number(0, 4), byte(4) == UInt8(ascii: "-"),
              let month = number(5, 2), byte(7) == UInt8(ascii: "-"),
              let day = number(8, 2), byte(10) == UInt8(ascii: "T"),
              let hour = number(11, 2), byte(13) == UInt8(ascii: ":"),
              let minute = number(14, 2), byte(16) == UInt8(ascii: ":"),
              let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 62 else { return nil }
        let seconds = epochDay(year: year, month: month, day: day) * 86_400
            + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public static func parse(_ text: String) -> Date? { parse(Array(text.utf8)) }

    /// Days from 1970-01-01 to a proleptic Gregorian date. Howard Hinnant's
    /// `days_from_civil`, which is exact for every year a transcript can carry and
    /// needs no calendar, no locale and no allocation.
    static func epochDay(year: Int, month: Int, day: Int) -> Int {
        let shifted = year - (month <= 2 ? 1 : 0)
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
