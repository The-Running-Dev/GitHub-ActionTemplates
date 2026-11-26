using Xunit;

namespace Fixture.Platforms.Tests;

// Split by platform, these run in the BuildAgent image only; Windows would fail them.
public class PlatformTests
{
    [Fact]
    public void RunsOnLinux() => Assert.Equal("Linux", Platform.Name);

    [Fact]
    public void RunsInTheImage() => Assert.True(Platform.InContainer);
}
