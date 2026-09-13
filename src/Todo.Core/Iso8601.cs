using System.Globalization;

namespace Todo.Core;

/// <summary>
/// Shared ISO 8601 formatting for dates that cross a text boundary (SQLite TEXT columns,
/// the Worker's JSON wire contract). Both the local upsert and the Worker's upsert compare
/// `updated_at` as a plain string, so every producer of that string must use this exact
/// format — round-tripping through anything else risks breaking the last-write-wins check.
/// </summary>
public static class Iso8601
{
    public static string Format(DateTimeOffset value) => value.ToString("O", CultureInfo.InvariantCulture);

    public static DateTimeOffset Parse(string value) => DateTimeOffset.Parse(value, CultureInfo.InvariantCulture);
}
