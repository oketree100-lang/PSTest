[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0)]
    [string]$Command,
    [string]$Port,
    [string]$IP,
    [string]$Name
)

$rootPath = Join-Path $env:LOCALAPPDATA "PSTest"
$configPath = Join-Path $rootPath "client_config.txt"

if (-not (Test-Path -Path $rootPath -PathType Container)) {
    [void](New-Item -Path $rootPath -Type Container)
}

if (-not (Test-Path -Path $configPath -PathType Leaf)) {
    [void](New-Item -Path $configPath -Type File)

    Add-Content -Path $configPath -Value ("`n" * 2)
    Add-Content -Path $configPath -Value "Guest"
}

$configContent = Get-Content $configPath

if ($Command -eq "setport") {
    $configContent[0] = $Port

    $configContent | Set-Content $configPath
} elseif ($Command -eq "setname") {
    $configContent[2] = $Name

    $configContent | Set-Content $configPath
} elseif ($Command -eq "sethost") {
    $configContent[1] = $IP

    $configContent | Set-Content $configPath
} elseif ($Command -eq "connect") {
    $client = [System.Net.Sockets.TcpClient]::new()
    
    try {
        

        $connection = $client.ConnectAsync($configContent[1], $configContent[0])
        
        $completed = $connection.Wait(3000)

        if ($completed -and $client.Connect) {
            Write-Host "Host available"

            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $writer = [System.IO.StreamWriter]::new($stream)
            $writer.AutoFlush = $true
            
            $writer.WriteLine($configContent[2])

            while ($true) {
                $content = $reader.ReadLine()

                if ($content -eq "Connection-Test") {
                    $writer.WriteLine("Connection-Test")
                }
                
                Start-Sleep -Milliseconds 300
            }
        } else {
            Write-Host "Host offline"
        }
    }
    finally {
        $client.Dispose()
    }
}