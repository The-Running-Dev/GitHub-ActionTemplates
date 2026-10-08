#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for the shared helpers that find and read report files.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'actions' '_lib' 'Functions.psm1') -Force
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'

    function New-TestFile([string] $Name, [string] $Text) {
        $path = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $path -Value $Text
        return $path
    }
}

Describe 'Find-WorkspaceFile' {
    BeforeAll {
        $script:Workspace = Join-Path $TestDrive 'find'
        foreach ($file in 'a.xml', 'reports/b.xml', 'reports/deep/c.xml', 'node_modules/pkg/d.xml', 'other/e.txt') {
            $path = Join-Path $Workspace $file
            New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value 'x'
        }
        function Get-Relative([string[]] $Paths) { @($Paths | Where-Object { $_ } | ForEach-Object { [System.IO.Path]::GetRelativePath($Workspace, $_).Replace('\', '/') }) }
    }

    It 'finds <Pattern>' -ForEach @(
        @{ Pattern = 'a.xml'; Expected = @('a.xml') }
        @{ Pattern = 'reports/*.xml'; Expected = @('reports/b.xml') }
        @{ Pattern = '**/*.xml'; Expected = @('a.xml', 'reports/b.xml', 'reports/deep/c.xml') }
        @{ Pattern = 'reports/**/c.xml'; Expected = @('reports/deep/c.xml') }
        @{ Pattern = '**/b.xml'; Expected = @('reports/b.xml') }
        @{ Pattern = 'missing.xml'; Expected = @() }
        @{ Pattern = 'missing/**/x.xml'; Expected = @() }
    ) {
        $found = Get-Relative (Find-WorkspaceFile -Pattern $Pattern -Workspace $Workspace)
        @($found | Sort-Object) | Should -Be @($Expected | Sort-Object)
    }

    It 'returns each file once across patterns' {
        @(Find-WorkspaceFile -Pattern 'a.xml', '**/a.xml' -Workspace $Workspace) | Should -HaveCount 1
    }

    It 'rejects a path outside the workspace' {
        { Find-WorkspaceFile -Pattern '../x.xml' -Workspace $Workspace } | Should -Throw '*must be inside the workspace*'
    }
}

Describe 'Get-CoverageReport' {
    It 'reads <Format>' -ForEach @(
        @{
            Format = 'Cobertura'; Name = 'cobertura.xml'; Covered = 3; Total = 4
            Text   = '<?xml version="1.0"?><coverage line-rate="0.75" lines-covered="3" lines-valid="4"><packages/></coverage>'
        }
        @{
            Format = 'JaCoCo'; Name = 'jacoco.xml'; Covered = 7; Total = 10
            Text   = "<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"no`"?>`n" +
            "<!DOCTYPE report PUBLIC `"-//JACOCO//DTD Report 1.1//EN`" `"report.dtd`">`n" +
            '<report name="Pester"><package name="p"><counter type="LINE" missed="9" covered="1"/></package>' +
            '<counter type="INSTRUCTION" missed="1" covered="1"/><counter type="LINE" missed="3" covered="7"/></report>'
        }
        @{
            Format = 'LCOV'; Name = 'lcov.info'; Covered = 5; Total = 8
            Text   = "TN:`nSF:a.js`nLF:5`nLH:4`nend_of_record`nSF:b.js`nLF:3`nLH:1`nend_of_record"
        }
    ) {
        $report = Get-CoverageReport (New-TestFile $Name $Text)

        $report.Format | Should -Be $Format
        $report.Covered | Should -Be $Covered
        $report.Total | Should -Be $Total
    }

    It 'counts Cobertura line hits when the totals are missing' {
        $path = New-TestFile 'cobertura-lines.xml' ('<coverage><packages><package><classes><class><lines>' +
            '<line number="1" hits="2"/><line number="2" hits="0"/><line number="3" hits="1"/>' +
            '</lines></class></classes></package></packages></coverage>')

        $report = Get-CoverageReport $path

        $report.Covered | Should -Be 2
        $report.Total | Should -Be 3
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'other.xml'; Text = '<testsuites/>'; Message = '*root element <testsuites>*' }
        @{ Name = 'other.txt'; Text = 'hello'; Message = '*not a Cobertura, JaCoCo or LCOV report*' }
    ) {
        { Get-CoverageReport (New-TestFile $Name $Text) } | Should -Throw $Message
    }
}

Describe 'Get-TestResult' {
    It 'reads <Format>' -ForEach @(
        @{
            Format = 'JUnit'; Name = 'junit.xml'; Passed = 1; Failed = 2; Skipped = 1; Failure = 'fails'
            Text   = '<testsuites><testsuite name="s"><testcase name="passes"/>' +
            '<testcase name="fails"><failure message="expected 1">stack</failure></testcase>' +
            '<testcase name="errors"><error>boom</error></testcase>' +
            '<testcase name="skips"><skipped/></testcase></testsuite></testsuites>'
        }
        @{
            Format = 'NUnit 2'; Name = 'nunit2.xml'; Passed = 1; Failed = 1; Skipped = 1; Failure = 'Suite.fails'
            Text   = '<test-results total="3"><test-suite><results>' +
            '<test-case name="Suite.passes" executed="True" result="Success"/>' +
            '<test-case name="Suite.fails" executed="True" result="Failure"><failure><message>expected 1</message></failure></test-case>' +
            '<test-case name="Suite.skips" executed="False" result="Ignored"/></results></test-suite></test-results>'
        }
        @{
            Format = 'NUnit 3'; Name = 'nunit3.xml'; Passed = 1; Failed = 1; Skipped = 1; Failure = 'Suite.fails'
            Text   = '<test-run><test-suite><test-case name="passes" fullname="Suite.passes" result="Passed"/>' +
            '<test-case name="fails" fullname="Suite.fails" result="Failed"><failure><message>expected 1</message></failure></test-case>' +
            '<test-case name="skips" fullname="Suite.skips" result="Skipped"/></test-suite></test-run>'
        }
        @{
            Format = 'TRX'; Name = 'results.trx'; Passed = 1; Failed = 1; Skipped = 1; Failure = 'fails'
            Text   = '<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>' +
            '<UnitTestResult testName="passes" outcome="Passed"/>' +
            '<UnitTestResult testName="fails" outcome="Failed"><Output><ErrorInfo><Message>expected 1</Message></ErrorInfo></Output></UnitTestResult>' +
            '<UnitTestResult testName="skips" outcome="NotExecuted"/></Results></TestRun>'
        }
    ) {
        $result = Get-TestResult (New-TestFile $Name $Text)

        $result.Format | Should -Be $Format
        $result.Total | Should -Be ($Passed + $Failed + $Skipped)
        $result.Passed | Should -Be $Passed
        $result.Failed | Should -Be $Failed
        $result.Skipped | Should -Be $Skipped
        $result.Failures[0].Name | Should -Be $Failure
        $result.Failures[0].Message | Should -Be 'expected 1'
    }

    It 'rejects a file that is not a results file' {
        { Get-TestResult (New-TestFile 'not-results.xml' '<coverage/>') } | Should -Throw '*root element <coverage>*'
    }
}

Describe 'Get-TarballManifest' {
    It 'reads package.json from a packed tarball' {
        $destination = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'packed')
        Push-Location (Join-Path $Fixtures 'npm-lib')
        try { $file = (npm pack --json --pack-destination $destination.FullName | ConvertFrom-Json)[0].filename }
        finally { Pop-Location }

        $manifest = Get-TarballManifest (Join-Path $destination $file)

        $manifest.name | Should -Be 'fixture-npm-lib'
        $manifest.version | Should -Be '2.3.4'
    }
}

Describe 'Format-MarkdownCell' {
    It 'keeps text on one line and escapes pipes' {
        Format-MarkdownCell "a | b`n  c" | Should -Be 'a \| b c'
    }

    It 'cuts long text' {
        Format-MarkdownCell ('x' * 30) 10 | Should -Be ('x' * 9 + "`u{2026}")
    }
}

Describe 'Write-ActionAnnotation' {
    It 'escapes the message and properties' {
        Mock Write-Host { } -ModuleName Functions

        Write-ActionAnnotation error "50% done`nnext" -File 'a,b.ps1' -Line 3 -Column 4 -Title 'Tests: unit'

        Should -Invoke Write-Host -ModuleName Functions -ParameterFilter {
            $Object -eq '::error file=a%2Cb.ps1,line=3,col=4,title=Tests%3A unit::50%25 done%0Anext'
        }
    }
}
