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
                
                if ($content -eq "Selected") {
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

                    $bitmap = [System.Drawing.Bitmap]::new(
                        $bounds.Width,
                        $bounds.Height
                    )

                    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

                    while ($true) {
                        $byte = $stream.ReadByte()
                        
                        if ($byte -eq 1) {
                            break
                        }

                        $graphics.CopyFromScreen(
                            $bounds.Location,
                            [System.Drawing.Point]::Empty,
                            $bounds.Size
                        )

                        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                            Where-Object { $_.MimeType -eq "image/jpeg" }

                        $quality = [System.Drawing.Imaging.Encoder]::Quality
                        $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
                        $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
                            $quality, [long]40
                        )

                        $memoryStream = [System.IO.MemoryStream]::new()

                        $bitmap.Save($memoryStream, $encoder, $parameters)

                        $pngBytes = $memoryStream.ToArray()
                        $memoryStream.Dispose()

                        $lengthBytes = [System.BitConverter]::GetBytes([int]$pngBytes.Length)

                        $stream.Write($lengthBytes, 0, 4)
                        $stream.Write($pngBytes, 0, $pngBytes.Length)
                    }
                }

                Start-Sleep -Milliseconds 300
            }
        } else {
            Write-Host "Host offline"
        }
    }
    finally {
        $client.Dispose()

        if ($null -ne $form) {
            $form.Dispose()
        }
    }
} else {
    Write-Host "Unknown command"
}