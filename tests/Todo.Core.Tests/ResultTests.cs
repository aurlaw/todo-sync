namespace Todo.Core.Tests;

public class ResultTests
{
    [Fact]
    public void Ok_produces_success_result_with_value()
    {
        var result = Result.Ok(42);

        Assert.True(result.IsSuccess);
        Assert.False(result.IsFailure);
        Assert.Equal(42, result.Value);
    }

    [Fact]
    public void Fail_produces_failure_result_with_error()
    {
        var result = Result.Fail<int>("boom");

        Assert.False(result.IsSuccess);
        Assert.True(result.IsFailure);
        Assert.Equal("boom", result.Error);
    }

    [Fact]
    public void Value_on_failed_result_throws()
    {
        var result = Result.Fail<int>("boom");

        Assert.Throws<InvalidOperationException>(() => result.Value);
    }

    [Fact]
    public void NonGeneric_Ok_and_Fail_report_success_state()
    {
        Assert.True(Result.Ok().IsSuccess);
        Assert.False(Result.Fail("nope").IsSuccess);
    }
}
