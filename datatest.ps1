param(
    [string]$command,
    [string]$ip = "null"
)

$ipHistoryRoot = Join-Path $env:LOCALAPPDATA "PSTest"
$ipHistoryPath = Join-Path $env:LOCALAPPDATA "PSTest/ip_history.txt"

if ($command -eq "list" ) {
    if (Test-Path -Path $ipHistoryPath -Type Leaf) {
        $content = Get-Content $ipHistoryPath

        Write-Host ("{0, -17} | Status" -f "IP")
        Write-Host ("-" * 17) "|" ("-" * 10)

        foreach ($line in $content) {
            Write-Host ("{0, -17} | " -f "$line") -NoNewline
            Write-Host "Online" -ForegroundColor Green
        }
    }
} elseif ($command -eq "add") {
    if (-not (Test-Path -Path $ipHistoryRoot -Type Container)) {
        [void](New-Item -Path $ipHistoryRoot -ItemType Container)
    }
    if (-not (Test-Path -Path $ipHistoryPath -Type Leaf)) {
        [void](New-Item -Path $ipHistoryPath -ItemType File)
    }

    Add-Content -Path $ipHistoryPath -Value $ip
} else {
    Write-Host "Unknown command"
}