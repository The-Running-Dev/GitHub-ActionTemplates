using Xunit;

namespace Fixture.Platforms.Windows.Tests;

// Split by platform, these run on Windows only.
public class WindowsPlatformTests
{
    [Fact]
    public void RunsOnWindows() => Assert.Equal("Windows", Platform.Name);
}
