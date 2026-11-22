param(
    [int]$Port
)

$listener = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Any,
    $Port
)

$listener.Start()

Write-Host "Server listening on port $($Port)..."

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()

        Write-Host "Client Connected!"

        $stream = $client.GetStream()
        $reader = [System.IO.StreamReader]::new($stream)
        $writer = [System.IO.StreamWriter]::new($stream)
        $writer.AutoFlush = $true

        try {
            while ($null -ne ($message = $reader.ReadLine())) {
                Write-Host "Received: $message"

                $writer.WriteLine("Server received: $message")
            }
        }
        finally {
            $reader.Dispose()
            $writer.Dispose()
            $client.Dispose()
            Write-Host "Client disconnected."
        }
    }
}
finally {
    $listener.Stop()
}