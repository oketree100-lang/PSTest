[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0)]
    [string]$Command,
    [string]$Port,
    [string]$IP,
    [string]$Name
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DPI {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@

[void][DPI]::SetProcessDPIAware()

Add-Type -AssemblyName System.Windows.Forms

$rootPath = Join-Path $env:LOCALAPPDATA "PSTest"
$configPath = Join-Path $rootPath "client_config.txt"

function Initialize-CliEnvironment {
    if (-not (Test-Path -Path $rootPath -PathType Container)) {
        [void](New-Item -Path $rootPath -Type Container)
    }

    if (-not (Test-Path -Path $configPath -PathType Leaf)) {
        [void](New-Item -Path $configPath -Type File)

        Add-Content -Path $configPath -Value ("`n" * 2)
        Add-Content -Path $configPath -Value "Guest"
    }
}

function Set-Port {
    $configContent[0] = $Port

    $configContent | Set-Content $configPath
}

function Start-RemoteSession {
    $stream = $client.GetStream()

    $stream.WriteByte(1)

    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    $bitmap = [System.Drawing.Bitmap]::new(
        $bounds.Width,
        $bounds.Height
    )

    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" }

    $quality = [System.Drawing.Imaging.Encoder]::Quality
    $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
        $quality, [long]50
    )

    $memoryStream = [System.IO.MemoryStream]::new()

    while ($true) {
        switch ($stream.ReadByte()) {
            -1 { break }
            2 {
                $mouseBytes = [byte[]]::new(8)
                
                $offset = 0

                while ($offset -lt 8) {
                    $read = $stream.Read($mouseBytes, $offset, 8 - $offset)
                    $offset += $read
                }
                
                $x = [System.BitConverter]::ToInt32($mouseBytes, 0)
                $y = [System.BitConverter]::ToInt32($mouseBytes, 4)

                [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($x, $y)
            }
        }

        $memoryStream.SetLength(0)
        $memoryStream.Position = 0

        $graphics.CopyFromScreen(
            $bounds.Location,
            [System.Drawing.Point]::Empty,
            $bounds.Size
        )

        $bitmap.Save($memoryStream, $encoder, $parameters)

        $imageBytes = $memoryStream.ToArray()

        $lengthBytes = [System.BitConverter]::GetBytes([int]$imageBytes.Length)

        $stream.Write($lengthBytes, 0, 4)
        $stream.Write($imageBytes, 0, $imageBytes.Length)
    }

    $memoryStream.Dispose()
    $parameters.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Start-HostSession {
    param(
        [Parameter(Mandatory)]
        [System.Net.Sockets.TcpClient]$Client
    )

    $stream = $Client.GetStream()
    $stream.ReadTimeout = 3000

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($configContent[2])
    $stream.WriteByte($bytes.Count)
    $stream.Write($bytes, 0, $bytes.Count)

    Write-Host 'Sent username'

    while ($true) {
        try {
            do {
                $command = $stream.ReadByte()
                
                switch ($command) {
                    -1 { break }
                    0 { $stream.WriteByte(0) }
                    1 { Start-RemoteSession }
                }
            } while ($stream.DataAvailable)
        }
        catch [System.IO.IOException] {
            break
        }

        Start-Sleep -Milliseconds 300
    }

    Write-Host 'Finished host session'
}

function Find-Host {
    while ($true) {
        $client = [System.Net.Sockets.TcpClient]::new()

        try {
            Write-Host 'Searching for host...'

            $task = $client.ConnectAsync($configContent[1], $configContent[0])

            while ($true) {
                if ($task.Status -eq 'RanToCompletion') {
                    Write-Host 'Found host'
                    Start-HostSession $client
                    break
                } elseif ($task.Status -eq "Faulted") {
                    break
                } else {
                    Start-Sleep -Milliseconds 300
                }
            }
        }
        finally {
            $client.Dispose()
        }
    }
}


$configContent = Get-Content -Path $configPath

Initialize-CliEnvironment

switch ($Command) {
    'set-port' { Set-Port }
    'connect' { Find-Host }
    default { Write-Host "Unknown command" }
}