function Get-FixtureSum {
    [CmdletBinding()]
    [OutputType([int])]
    param([int[]] $Number = @())

    $total = 0
    foreach ($value in $Number) { $total += $value }
    return $total
}

function Get-FixtureGreeting {
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Name = '')

    if (-not $Name) { return 'Hello.' }
    return "Hello, $Name."
}

Export-ModuleMember -Function Get-FixtureSum, Get-FixtureGreeting
