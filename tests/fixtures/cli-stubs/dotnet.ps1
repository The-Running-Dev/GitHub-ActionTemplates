# Stands in for the .NET CLI in the dotnet-test, dotnet-pack and nuget-push tests. Appends each call's
# arguments to $env:STUB_LOG/dotnet.txt.
# - `test` writes a TRX file to --results-directory and, with --collect, a Cobertura report per name
#   in STUB_COVERAGE_PROJECTS (comma-separated), plus the copy coverlet leaves under In/. It exits
#   with STUB_TEST_EXIT.
# - `pack` writes <name>.<version>.nupkg and .snupkg to --output for each name in STUB_PACKAGES,
#   with the version from the last -p:Version= (else STUB_PACKAGE_VERSION, else 1.0.0).
# - `nuget push` exits with STUB_PUSH_EXIT.
$log = Join-Path $env:STUB_LOG 'dotnet.txt'
Add-Content -LiteralPath $log -Value ($args -join ' ')

switch ($args[0]) {
    'test' {
        $results = $args[[array]::IndexOf($args, '--results-directory') + 1]
        New-Item -ItemType Directory -Force -Path $results | Out-Null
        Set-Content -LiteralPath (Join-Path $results 'run.trx') -Value '<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><ResultSummary outcome="Completed"><Counters total="2" executed="2" passed="2" failed="0" /></ResultSummary></TestRun>'
        if ($args -contains '--collect') {
            foreach ($project in "$env:STUB_COVERAGE_PROJECTS".Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                $folder = Join-Path $results ([guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Force -Path $folder | Out-Null
                $report = @"
<coverage line-rate="0.5" lines-covered="1" lines-valid="2" version="1.9"><sources><source>/src/</source></sources><packages><package name="Lib"><classes>
<class name="Lib.Calc" filename="Calc.cs"><lines><line number="1" hits="$(if ($project -eq 'b') { 0 } else { 3 })" /><line number="2" hits="$(if ($project -eq 'b') { 2 } else { 0 })" /></lines></class>
</classes></package></packages></coverage>
"@
                Set-Content -LiteralPath (Join-Path $folder 'coverage.cobertura.xml') -Value $report
                $copy = Join-Path $results 'run' 'In' 'machine'
                New-Item -ItemType Directory -Force -Path $copy | Out-Null
                Set-Content -LiteralPath (Join-Path $copy 'coverage.cobertura.xml') -Value $report
            }
        }
        exit [int] "0$env:STUB_TEST_EXIT"
    }
    'pack' {
        $output = $args[[array]::IndexOf($args, '--output') + 1]
        $version = ($args | Where-Object { $_ -like '-p:Version=*' } | ForEach-Object { $_.Substring(11) } | Select-Object -Last 1) ?? $env:STUB_PACKAGE_VERSION
        if (-not $version) { $version = '1.0.0' }
        foreach ($name in "$env:STUB_PACKAGES".Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $file = $version.Split('+')[0]
            Set-Content -LiteralPath (Join-Path $output "$name.$file.nupkg") -Value 'nupkg'
            Set-Content -LiteralPath (Join-Path $output "$name.$file.snupkg") -Value 'snupkg'
        }
        exit 0
    }
    'nuget' { exit [int] "0$env:STUB_PUSH_EXIT" }
}
exit 0
