#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Checks each action.yml against its script. The action scripts are tested directly, so a broken
# action.yml would otherwise only show up when a workflow loads it.

BeforeDiscovery {
    $script:ActionCases = Get-ChildItem (Join-Path $PSScriptRoot '..' 'actions') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'action.yml') } |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

Describe '<Name> metadata' -ForEach $ActionCases {
    BeforeAll {
        $script:Lines = @(Get-Content -LiteralPath (Join-Path $Path 'action.yml'))
        $script:Text = $Lines -join "`n"
        $inputBlock = [regex]::Match($Text, '(?ms)^inputs:\s*\n(.*?)(?=^\S)').Groups[1].Value
        $script:Inputs = @([regex]::Matches($inputBlock, '(?m)^  ([a-z0-9-]+):') | ForEach-Object { $_.Groups[1].Value })
        $script:Scripts = @(Get-ChildItem -LiteralPath $Path -Filter '*.ps1' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw })
    }

    It 'has no plain-scalar value containing ": "' {
        # YAML reads `key: text: more` as a nested mapping, so such a value must be quoted.
        $bad = $Lines | Where-Object { $_ -match '^\s*(-\s+)?[a-z0-9_-]+:\s+(?![''">|&*!{\[])[^#]*:\s' }
        $bad | Should -BeNullOrEmpty
    }

    It 'uses every input it declares' {
        foreach ($name in $Inputs) {
            $Text | Should -Match ("inputs\.$([regex]::Escape($name))(?![a-z0-9-])") -Because "input '$name' is declared"
        }
    }

    It 'maps each INPUT_ variable to its input' {
        foreach ($m in [regex]::Matches($Text, 'INPUT_([A-Z0-9_]+):\s*\$\{\{\s*inputs\.([a-z0-9-]+)\s*\}\}')) {
            $m.Groups[1].Value | Should -BeExactly ($m.Groups[2].Value.ToUpperInvariant() -replace '-', '_')
        }
    }

    It 'declares every input its script reads' {
        $read = $Scripts | ForEach-Object { [regex]::Matches($_, "Get-ActionInput\s+'([a-z0-9-]+)'") } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        foreach ($name in $read) { $Inputs | Should -Contain $name -Because "the script reads '$name'" }
    }
}
