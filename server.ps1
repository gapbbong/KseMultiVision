$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")
try {
    $listener.Start()
    Write-Host "PowerShell HTTP Server started successfully."
    Write-Host "Listening on http://localhost:8080/ ..."
    
    # Keep listening in a loop
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $path = $request.Url.LocalPath
            if ($path -eq "/proxy") {
                $id = $request.QueryString["id"]
                $type = $request.QueryString["type"]
                
                $url = ""
                if ($type -eq "video") {
                    $url = "https://drive.usercontent.google.com/download?id=$id&export=download"
                } else {
                    $url = "https://lh3.googleusercontent.com/d/$id=w1280"
                }
                
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $bytes = $wc.DownloadData($url)
                    
                    if ($type -eq "video") {
                        $response.ContentType = "video/mp4"
                    } else {
                        $response.ContentType = "image/jpeg"
                    }
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                } catch {
                    $response.StatusCode = 500
                    $errMsg = [System.Text.Encoding]::UTF8.GetBytes("Error proxying data: $_")
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $errMsg.Length
                    $response.OutputStream.Write($errMsg, 0, $errMsg.Length)
                }
                $response.Close()
                continue
            }
            
            if ($path -eq "" -or $path -eq "/") {
                $path = "/index.html"
            }
            
            # Map request to local file in the same directory
            $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            $filePath = Join-Path $currentDir $path.TrimStart('/')
            
            if (Test-Path $filePath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                
                # Determine Content-Type
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $contentType = "application/octet-stream"
                if ($ext -eq ".html" -or $ext -eq ".htm") { $contentType = "text/html; charset=utf-8" }
                elseif ($ext -eq ".css") { $contentType = "text/css" }
                elseif ($ext -eq ".js") { $contentType = "application/javascript" }
                elseif ($ext -eq ".png") { $contentType = "image/png" }
                elseif ($ext -eq ".jpg" -or $ext -eq ".jpeg") { $contentType = "image/jpeg" }
                elseif ($ext -eq ".mp3") { $contentType = "audio/mpeg" }
                elseif ($ext -eq ".mp4") { $contentType = "video/mp4" }
                
                $response.ContentType = $contentType
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $errMsg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $response.ContentType = "text/plain; charset=utf-8"
                $response.ContentLength64 = $errMsg.Length
                $response.OutputStream.Write($errMsg, 0, $errMsg.Length)
            }
            $response.Close()
        } catch {
            # Catch internal handler errors and continue listening
        }
    }
} catch {
    Write-Error "Failed to start HTTP Listener. Port 8080 might be in use or requires Administrator privilege."
} finally {
    if ($listener -ne $null) {
        $listener.Close()
    }
}
