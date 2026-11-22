$port = 0
while (-not [int]::TryParse((Read-Host "Port"), [ref]$port)) {
    Write-Host "Invalud input. Please enter a whole number"
}

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Any,
    $Port
)

$listener.Start()

Write-Host "Server listening on port $($Port)..."

$clients = [System.Collections.Generic.List[object]]::new()

try {
    while ($listener.Server.IsBound) {
        if ($listener.Pending()) {
            $clients.Add($listener.AcceptTcpClient())
        }

        for ($i = $clients.Count - 1; $i -ge 0; $i--) {
            $client = $clients[$i]
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream)

            if ($reader.BaseStream.DataAvailable) {
                $content = $reader.ReadLine()
                Write-Host "Received: $content"
            }

            if ($client.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $client.Available -eq 0) {
                $stream.Dispose()
                $reader.Dispose()
                $client.Dispose()
                $clients.RemoveAt($i)
            }
        }

        Start-Sleep -Milliseconds 1000
    }
}
finally {
    $listener.Stop()
    Write-Host "Server closed"
}