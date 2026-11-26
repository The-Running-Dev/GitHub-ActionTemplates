namespace Fixture.Platforms;

public static class Platform
{
    public static string Name => OperatingSystem.IsWindows() ? "Windows" : OperatingSystem.IsLinux() ? "Linux" : "Other";

    // Docker writes /.dockerenv into every container.
    public static bool InContainer => File.Exists("/.dockerenv");
}
