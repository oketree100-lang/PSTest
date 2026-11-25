[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0)]
    [string]$Command,
    [string]$Port
)

$rootPath = Join-Path $env:LOCALAPPDATA "PSTest"
$configPath = Join-Path $rootPath "host_config.txt"

if (-not (Test-Path -Path $rootPath -PathType Container)) {
    [void](New-Item -Path $rootPath -Type Container)
}

if (-not (Test-Path -Path $configPath -PathType Leaf)) {
    [void](New-Item -Path $configPath -Type File)

    Add-Content -Path $configPath -Value "`n"
}

$configContent = Get-Content $configPath

if ($Command -eq "setport") {
    $configContent[0] = $Port

    $configContent | Set-Content $configPath
} elseif ($Command -eq "listen") {
    try {
        [System.Console]::CursorVisible = $false

        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Any,
            $configContent[0]
        )

        $clients = [System.Collections.Generic.List[System.Net.Sockets.TcpClient]]::new()
        $usernames = [System.Collections.Generic.List[string]]::new()

        $listener.Start()

        $selected = 0

        Clear-Host
        Write-Host "Listening for clients" -NoNewline
        [System.Console]::SetCursorPosition(0, 0)

        while ($true) {
            while ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)

                if ($selected -lt $clients.Count) {
                    [System.Console]::SetCursorPosition(0, $selected)
                    Write-Host "Username: $($usernames[$selected])       "
                }

                if ($key.Key -eq "UpArrow" -and $selected -gt 0) {
                    $selected--
                } elseif ($key.Key -eq "DownArrow" -and $selected -lt $clients.Count - 1) {
                    $selected++
                }

                if ($selected -lt $clients.Count) {
                    [System.Console]::SetCursorPosition(0, $selected)
                    Write-Host "> Username: $($usernames[$selected])       "
                }
            }

            if ($listener.Pending()) {
                $client = $listener.AcceptTcpClient()
                $clients.Add($client)

                $stream = $client.GetStream()
                $reader = [System.IO.StreamReader]::new($stream)

                [string]$username = $reader.ReadLine()

                $usernames.Add($username)

                Write-Host "Username: $username       "
            }

            for ($i = $clients.Count - 1; $i -ge 0; $i--) {
                $client = $clients[$i];

                $stream = $client.GetStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $writer = [System.IO.StreamWriter]::new($stream)
                $writer.AutoFlush = $true
                
                $writer.WriteLine("Connection-Test")
                
                $reachable = $true

                try {
                    $content = $reader.ReadLine()
                }
                catch {
                    $reachable = $false
                }

                if (-not $reachable -or $null -eq $content) {
                    $client.Dispose()
                    $idx = $clients.IndexOf($client)
                    [void]$clients.RemoveAt($idx)
                    [void]$usernames.RemoveAt($idx)

                    Clear-Host
                    
                    if ($clients.Count -eq 0) {
                        Write-Host "Listening for clients" -NoNewline
                        [System.Console]::SetCursorPosition(0, 0)
                    } else {
                        foreach ($username in $usernames) {
                            Write-Host "Username: $username       "
                        }
                    }
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        $listener.Stop()

        foreach ($client in $clients) {
            $client.Dispose()
        }
    }
}