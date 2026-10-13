namespace Fixture.Calculator;

public static class Calculator
{
    public static int Add(int left, int right) => left + right;

    public static int Divide(int dividend, int divisor)
    {
        if (divisor == 0)
        {
            throw new DivideByZeroException();
        }

        return dividend / divisor;
    }

    // Not covered by the tests, so the coverage is below 100%.
    public static int Negate(int value) => -value;
}
