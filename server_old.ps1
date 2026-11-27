[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0)]
    [string]$Command,
    [string]$Port
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class DpiNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@

try {
    $result = [DpiNative]::SetProcessDpiAwarenessContext([IntPtr](-4))

    if (-not $result) {
        [DpiNative]::SetProcessDPIAware()
    }
}
catch {
    [DpiNative]::SetProcessDPIAware()
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
                } elseif ($key.Key -eq "Enter") {
                    $client = $clients[$selected]

                    $stream = $client.GetStream()
                    $reader = [System.IO.StreamReader]::new($stream)
                    $writer = [System.IO.StreamWriter]::new($stream)
                    $writer.AutoFlush = $true

                    $stream.WriteByte(4)

                    $form = [System.Windows.Forms.Form]::new()
                    $form.Text = "Remote Client - $($usernames[$selected])"
                    $form.Width = 1000
                    $form.height = 700
                    $form.StartPosition = "CenterScreen"

                    $pictureBox = [System.Windows.Forms.PictureBox]::new()
                    $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
                    $pictureBox.Image = $null
                    $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

                    $form.Controls.Add($pictureBox)

                    [void]$form.Show()

                    try {
                        while ($form.Visible) {
                            $stream.WriteByte(0)

                            [System.Windows.Forms.Application]::DoEvents()

                            $lengthBytes = [byte[]]::new(4)
                            $offset = 0

                            while ($offset -lt 4) {
                                $read = $stream.Read($lengthBytes, $offset, 4 - $offset)
                                if ($read -eq 0) { throw "Client disconnected."}
                                $offset += $read
                            }

                            $imageLength = [System.BitConverter]::ToInt32($lengthBytes, 0)

                            if ($imageLength -le 0 -or $imageLength -gt 20MB) {
                                throw "Invalid image size."
                            }

                            $jpgBytes = [byte[]]::new($imageLength)
                            $offset = 0

                            while ($offset -lt $imageLength) {
                                $read = $stream.Read($jpgBytes, $offset, $imageLength - $offset)
                                if ($read -eq 0) { throw "Client disconnected."}
                                $offset += $read
                            }

                            if ($null -ne $image) {
                                $image.Dispose()
                            }

                            $ms = [System.IO.MemoryStream]::new($jpgBytes)
                            $image = [System.Drawing.Image]::FromStream($ms)

                            $pictureBox.Image = $image
                            
                            Start-Sleep -Milliseconds 5
                        }
                    }
                    finally {
                        $form.Dispose()

                        $stream.WriteByte(1)
                    }
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
                
                $stream.WriteByte(2)
                
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

        Write-Host $clients.Count

        foreach ($client in $clients) {
            $stream = $client.GetStream()
            $writer = [System.IO.StreamWriter]::new($stream)
            
            $stream.WriteByte(3)

            $client.Dispose()
        }

        [System.Console]::CursorVisible = $true
    }
} else {
    Write-Host "Unknown command"
}