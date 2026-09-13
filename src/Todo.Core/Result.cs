namespace Todo.Core;

public class Result
{
    public bool IsSuccess { get; }
    public string? Error { get; }

    protected Result(bool isSuccess, string? error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public bool IsFailure => !IsSuccess;

    public static Result Ok() => new(true, null);
    public static Result Fail(string error) => new(false, error);

    public static Result<T> Ok<T>(T value) => new(true, value, null);
    public static Result<T> Fail<T>(string error) => new(false, default, error);
}

public sealed class Result<T> : Result
{
    private readonly T? _value;

    internal Result(bool isSuccess, T? value, string? error)
        : base(isSuccess, error)
    {
        _value = value;
    }

    public T Value => IsSuccess
        ? _value!
        : throw new InvalidOperationException($"Cannot access Value on a failed Result. Error: {Error}");
}
