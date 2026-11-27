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
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
}
"@

[void][DpiNative]::SetThreadDpiAwarenessContext([IntPtr](-4))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$rootPath = Join-Path $env:LOCALAPPDATA "PSTest"
$configPath = Join-Path $rootPath "host_config.txt"

function Get-PictureBoxInfo {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.PictureBox]$PictureBox
    )

    if (-not $PictureBox.Image) { return $null }

    $pbWidth = $PictureBox.ClientSize.Width
    $pbHeight = $PictureBox.ClientSize.Height
    $imgWidth = $PictureBox.Image.Width
    $imgHeight = $PictureBox.Image.Height

    $ratioX = $pbWidth / $imgWidth
    $ratioY = $pbHeight / $imgHeight
    $ratio = [Math]::Min($ratioX, $ratioY)

    $renderedWidth = $imgWidth * $ratio
    $renderedHeight = $imgHeight * $ratio

    $offsetX = [int](($pbWidth - $renderedWidth) / 2)
    $offsetY = [int](($pbHeight - $renderedHeight) / 2)

    return [PSCustomObject]@{
        offsetX = $offsetX
        offsetY = $offsetY
        ratio = $ratio
    }
}

function Initialize-CliEnvironment {
    if (-not (Test-Path -Path $rootPath -PathType Container)) {
        [void](New-Item -Path $rootPath -Type Container)
    }
    
    if (-not (Test-Path -Path $configPath -PathType Leaf)) {
        [void](New-Item -Path $configPath -Type File)

        Add-Content -Path $configPath -Value "`n"
    }
}

function Set-Port {
    $configContent[0] = $Port

    $configContent | Set-Content $configPath
}

function Update-Client {
    [Parameter(Mandatory)]
    param(
        [System.Net.Sockets.TcpClient]$Client
    )

    $stream = $Client.GetStream()
    
    $disconnected = $false

    try {
        $stream.WriteByte(0)
        $disconnected = ($stream.ReadByte() -eq -1)
    }
    catch [System.IO.IOException] {
        $disconnected = $true
    }


    if ($disconnected) {
        $idx = $clients.IndexOf($Client)
        $clients.RemoveAt($idx)
        $usernames.RemoveAt($idx)
        
        $Client.Dispose()

        Clear-Host

        foreach ($username in $usernames) {
            Write-Host "Username: $username"
        }

        continue
    }

    $stream.WriteByte(0)
}

function Start-RemoteSession {
    [Parameter(Mandatory)]
    param(
        [System.Net.Sockets.TcpClient]$Client
    )

    $stream = $Client.GetStream()

    $stream.WriteByte(1)

    try {
        while ($stream.ReadByte() -ne 1) {}

        $form = [System.Windows.Forms.Form]::new()
        $form.Text = "Remote Client - $($usernames[$selected])"
        $form.Width = 1000
        $form.Height = 700
        $form.StartPosition = 'CenterScreen'
        
        $pictureBox = [System.Windows.Forms.PictureBox]::new()
        $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::zoom
        $pictureBox.Image = $null

        $form.Controls.Add($pictureBox)

        [void]$form.Show()

        $imageBytes = [byte[]]::new(0)

        $image = $null
        $memoryStream = $null

        while ($form.Visible) {
            $isFormSelected = [System.Windows.Forms.Form]::ActiveForm -eq $form
            $screenPos = [System.Windows.Forms.Cursor]::Position
            $clientPos = $pictureBox.PointToClient($screenPos)

            if ($isFormSelected -and $form.ClientRectangle.Contains($clientPos)) {
                $pbInfo = Get-PictureBoxInfo $pictureBox
                
                if ($null -ne $pbInfo -and $pbInfo.ratio -gt 0) {
                    [int32]$remoteX = ($clientPos.X - $pbInfo.offsetX) / $pbInfo.ratio
                    [int32]$remoteY = ($clientPos.Y - $pbInfo.offsetY) / $pbInfo.ratio

                    $stream.WriteByte(2)
                    Write-Host $pbInfo
                    [byte[]]$mouseBytes = [System.BitConverter]::GetBytes($remoteX) + [System.BitConverter]::GetBytes($remoteY)
                    $stream.Write($mouseBytes, 0, 8)
                } else {
                    $stream.WriteByte(0)
                }
            } else {
                $stream.WriteByte(0)
            }

            $lengthBytes = [byte[]]::new(4)
            $offset = 0

            while ($offset -lt 4) {
                $read = $stream.Read($lengthBytes, $offset, 4 - $offset)
                if ($read -eq 0) { throw 'Client disconnected' }
                $offset += $read
            }

            $imageLength = [System.BitConverter]::ToInt32($lengthBytes, 0)

            if ($imageLength -le 0 -or $imageLength -gt 20MB) {
                throw 'Invalid image size'
            }

            if ($imageBytes.Count -lt $imageLength) {
                $imageBytes = [byte[]]::new($imageLength)
            }
            $offset = 0

            while ($offset -lt $imageLength) {
                $read = $stream.Read($imageBytes, $offset, $imageLength - $offset)
                if ($read -eq 0) { throw 'Client disconnected' }
                $offset += $read
            }

            if ($null -ne $image) {
                $image.Dispose()
                $image = $null
            }
            if ($null -ne $memoryStream) {
                $memoryStream.Dispose()
                $memoryStream = $null
            }

            $memoryStream = [System.IO.MemoryStream]::new($imageBytes)

            $image = [System.Drawing.Image]::FromStream($memoryStream)

            $pictureBox.Image = $image

            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    finally {
        $form.Dispose()
        $pictureBox.Dispose()

        $stream.WriteByte(1)
    }
}

function Start-ClientListener {
    [System.Console]::CursorVisible = $false
    Clear-Host
    Write-Host 'Listening for clients...'

    $clients = [System.Collections.Generic.List[System.Net.Sockets.TcpClient]]::new()
    $usernames = [System.Collections.Generic.List[string]]::new()

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        $configContent[0]
    )

    $listener.Start()

    try {
        $selected = 0

        while ($true) {
            if ($listener.Pending()) {
                $client = $listener.AcceptTcpClient()
                $clients.Add($client)

                $stream = $client.GetStream()
                $stream.ReadTimeout = 3000

                $bytesLength = $stream.ReadByte()

                $bytes = [byte[]]::new($bytesLength)

                [void]$stream.Read($bytes, 0, $bytesLength)

                $username = [System.Text.Encoding]::UTF8.GetString($bytes)

                $usernames.Add($username)

                if ($clients.Count -eq 1) {
                    Clear-Host
                }

                Write-Host "Username: $username"
            }

            for ($i = $clients.Count - 1; $i -ge 0; $i--) {
                Update-Client $clients[$i]
            }

            $e = [char]27
            $buffer = [System.Text.StringBuilder]::new()

            [void]$buffer.Append("$e[?2026h")

            while ([System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)

                $row = $selected + 1
                [void]$buffer.Append("$e[${row};1H$e[2KUsername: $($usernames[$selected])")

                switch ($key.Key) {
                    'UpArrow' {
                        if ($selected -gt 0) { $selected-- }
                    }
                    'DownArrow' {
                        if ($selected -lt $clients.Count - 1) { $selected++ }
                    }
                    'Enter' {
                        if ($clients.Count -ne 0) {
                            Start-RemoteSession $clients[$selected]
                        }
                    }
                }

                $row = $selected + 1
                [void]$buffer.Append("$e[${row};1H$e[2K> Username: $($usernames[$selected])")
            }

            [void]$buffer.Append("$e[?2026l")

            [System.Console]::Write($buffer.ToString())

            Start-Sleep -Milliseconds 300
        }
    }
    finally {
        $listener.Stop()

        foreach ($client in $clients) {
            $client.Dispose()
        }

        [System.Console]::CursorVisible = $true
    }
}


$configContent = Get-Content -Path $configPath

Initialize-CliEnvironment

switch ($Command) {
    'setport' { Set-Port }
    'listen' { Start-ClientListener }
    default { Write-Host 'Unknown command' }
}