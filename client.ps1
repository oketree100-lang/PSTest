param(
    [int]$port
)

$client = [System.Net.Sockets.TcpClient]::new()

$client.Connect("127.0.0.1", $port)

$stream = $client.GetStream()

$reader = [System.IO.StreamReader]::new($stream)
$writer = [System.IO.StreamWriter]::new($stream)
$writer.AutoFLush = $true

try {
    while ($true) {
        $message = Read-Host "Message (exit to quit)"

        if ($message -eq "exit") {
            break
        }

        $writer.WriteLine($message)

        $response = $reader.ReadLine()

        Write-Host "Server: $response"
    }
}
finally {
    $reader.Dispose()
    $writer.Dispose()
    $client.Dispose()
}