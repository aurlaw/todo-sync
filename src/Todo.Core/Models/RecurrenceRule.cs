namespace Todo.Core.Models;

public enum RecurrenceFrequency
{
    Daily,
    Weekly,
    Monthly,
}

public sealed class RecurrenceRule
{
    public required RecurrenceFrequency Frequency { get; init; }

    public required int Interval { get; init; }

    /// <summary>Weekly only.</summary>
    public IReadOnlyList<DayOfWeek>? DaysOfWeek { get; init; }
}
