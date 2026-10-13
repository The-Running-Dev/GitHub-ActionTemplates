using Xunit;

namespace Fixture.Calculator.Tests;

public class CalculatorTests
{
    [Fact]
    public void AddsTwoNumbers() => Assert.Equal(5, Calculator.Add(2, 3));

    [Fact]
    public void DividesTwoNumbers() => Assert.Equal(4, Calculator.Divide(8, 2));

    [Fact]
    public void RejectsDivisionByZero() => Assert.Throws<DivideByZeroException>(() => Calculator.Divide(1, 0));

    // Excluded by the self-test's filter.
    [Fact]
    [Trait("Category", "Slow")]
    public void SlowTest() => Assert.Equal(2, Calculator.Add(1, 1));
}
