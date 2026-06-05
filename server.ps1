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
            if ($path -eq "/list") {
                $folderId = $request.QueryString["folderId"]
                $accessToken = $request.QueryString["access_token"]
                $apiKey = "AIzaSyCgjlRcgzTYBAf_21P-AJTSLTYlFvadavI"
                $folderName = $request.QueryString["folderName"]
                $url = "https://www.googleapis.com/drive/v3/files?q='$folderId'%20in%20parents&fields=files(id,name,mimeType,webContentLink)&supportsAllDrives=true&includeItemsFromAllDrives=true"
                
                if (-not [string]::IsNullOrEmpty($accessToken)) {
                    # Auth Header
                } elseif (-not [string]::IsNullOrEmpty($apiKey)) {
                    $url += "&key=$apiKey"
                }
                
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    if (-not [string]::IsNullOrEmpty($accessToken)) {
                        $wc.Headers.Add("Authorization", "Bearer $accessToken")
                    }
                    
                    Write-Host "[Proxy Server] Listing files in folder: $folderId"
                    $jsonBytes = $wc.DownloadData($url)
                    
                    $videosDir = "C:\Videos"
                    if (-not (Test-Path $videosDir)) {
                        New-Item -Path $videosDir -ItemType Directory -Force | Out-Null
                    }
                    
                    $keepIds = $request.QueryString["keep_ids"]
                    if (-not [string]::IsNullOrEmpty($accessToken) -and -not [string]::IsNullOrEmpty($keepIds)) {
                        $syncScript = Join-Path $PSScriptRoot "sync_videos.ps1"
                        
                        # Start background sync process silently without opening/flashing any console windows
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = "powershell.exe"
                        $folderNameArg = if ([string]::IsNullOrEmpty($folderName)) { $folderId } else { $folderName }
                        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$syncScript`" -folderId `"$folderId`" -accessToken `"$accessToken`" -keepIds `"$keepIds`" -folderName `"$folderNameArg`""
                        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                        $psi.CreateNoWindow = $true
                        $psi.UseShellExecute = $false
                        [System.Diagnostics.Process]::Start($psi) | Out-Null
                    }
                    
                    [System.IO.File]::WriteAllBytes("C:\Videos\debug_list.json", $jsonBytes)
                    
                    $response.ContentType = "application/json; charset=utf-8"
                    $response.ContentLength64 = $jsonBytes.Length
                    $response.OutputStream.Write($jsonBytes, 0, $jsonBytes.Length)
                } catch {
                    Write-Host "[Proxy Server] Error in /list: $_"
                    $response.StatusCode = 500
                    $errMsg = [System.Text.Encoding]::UTF8.GetBytes("Error listing drive: $_")
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $errMsg.Length
                    $response.OutputStream.Write($errMsg, 0, $errMsg.Length)
                }
                $response.Close()
                continue
            }
            
            if ($path -eq "/proxy") {
                $id = $request.QueryString["id"]
                $type = $request.QueryString["type"]
                $accessToken = $request.QueryString["access_token"]
                
                if ($type -eq "video") {
                    $localFile = Get-ChildItem -Path "C:\Videos" -Filter "$id.mp4" -Recurse | Select-Object -First 1
                    if ($localFile) {
                        $localVideoPath = $localFile.FullName
                        Write-Host "[Proxy Server] Serving LOCAL video for $id"
                        $response.ContentType = "video/mp4"
                        $fileInfo = New-Object System.IO.FileInfo($localVideoPath)
                        $response.ContentLength64 = $fileInfo.Length
                        $stream = [System.IO.File]::OpenRead($localVideoPath)
                        $buffer = New-Object byte[] 65536
                        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { try { $response.OutputStream.Write($buffer, 0, $read) } catch { break } }
                        $stream.Close()
                        $response.Close()
                        continue
                    }
                }
                
                try {
                    if ($type -eq "video") {
                        if (-not [string]::IsNullOrEmpty($accessToken)) {
                            $url = "https://www.googleapis.com/drive/v3/files/$id`?alt=media&supportsAllDrives=true"
                        } else {
                            $url = "https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"
                        }
                    } else {
                        $url = "https://lh3.googleusercontent.com/d/$id=w1280"
                    }
                    
                    $req = [System.Net.WebRequest]::Create($url)
                    $req.Method = "GET"
                    $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                    
                    if (-not [string]::IsNullOrEmpty($accessToken) -and $type -eq "video") {
                        $req.Headers.Add("Authorization", "Bearer $accessToken")
                    }
                    
                    $rangeHeader = $request.Headers["Range"]
                    if ($rangeHeader -and $type -eq "video") {
                        if ($rangeHeader -match "bytes=(\d+)-(\d*)") {
                            $start = $matches[1]
                            $end = $matches[2]
                            if ($end) {
                                $req.AddRange([long]$start, [long]$end)
                            } else {
                                $req.AddRange([long]$start)
                            }
                            $response.StatusCode = 206
                        }
                    }
                    
                    Write-Host "[Proxy Server] Fetching data from: $url (Range: $rangeHeader)"
                    $res = $req.GetResponse()
                    $stream = $res.GetResponseStream()
                    
                    if ($type -eq "video") {
                        $response.ContentType = "video/mp4"
                        $contentLength = $res.Headers["Content-Length"]
                        if ($contentLength) { $response.ContentLength64 = [long]$contentLength }
                        
                        $contentRange = $res.Headers["Content-Range"]
                        if ($contentRange) { $response.AddHeader("Content-Range", $contentRange) }
                        
                        $acceptRanges = $res.Headers["Accept-Ranges"]
                        if ($acceptRanges) { $response.AddHeader("Accept-Ranges", $acceptRanges) }
                        else { $response.AddHeader("Accept-Ranges", "bytes") }
                    } else {
                        $response.ContentType = "image/jpeg"
                    }
                    
                    $buffer = New-Object byte[] 65536
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { try { $response.OutputStream.Write($buffer, 0, $read) } catch { break } }
                    $stream.Close()
                    $res.Close()
                } catch {
                    Write-Host "[Proxy Server] Error proxying data: $_"
                    try {
                        $response.StatusCode = 500
                        $errMsg = [System.Text.Encoding]::UTF8.GetBytes("Error proxying data: $_")
                        $response.ContentType = "text/plain; charset=utf-8"
                        $response.ContentLength64 = $errMsg.Length
                        $response.OutputStream.Write($errMsg, 0, $errMsg.Length)
                    } catch {}
                }
                $response.Close()
                continue
            }
            
            if ($path -eq "/api/videos") {
                $videosDir = "C:\Videos"
                $fileList = @()
                if (Test-Path $videosDir) {
                    $files = Get-ChildItem -Path $videosDir -Filter "*.mp4" -Recurse
                    foreach ($f in $files) {
                        $obj = New-Object PSObject
                        $obj | Add-Member -MemberType NoteProperty -Name "name" -Value $f.Name
                        $obj | Add-Member -MemberType NoteProperty -Name "url" -Value "/local/$($f.Name)"
                        $fileList += $obj
                    }
                }
                
                if ($fileList.Count -eq 0) { 
                    $json = "[]" 
                } else {
                    # ConvertTo-Json behavior with 1 element requires an array wrapper, but we handle it manually or use -AsArray in PS Core. For PS 5, we can use an array wrapper.
                    $json = @($fileList) | ConvertTo-Json -Compress
                }
                
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
                continue
            }
            
            if ($path -match "^/local/(.*)$") {
                $fileName = [System.Uri]::UnescapeDataString($matches[1])
                $videosDir = "C:\Videos"
                $localFile = Get-ChildItem -Path $videosDir -Filter $fileName -Recurse | Select-Object -First 1
                if ($localFile) {
                    $filePath = $localFile.FullName
                    $response.ContentType = "video/mp4"
                    $stream = [System.IO.File]::OpenRead($filePath)
                    $buffer = New-Object byte[] 65536
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { try { $response.OutputStream.Write($buffer, 0, $read) } catch { break } }
                    $stream.Close()
                } else {
                    $response.StatusCode = 404
                }
                $response.Close()
                continue
            }
            
            if ($path -eq "" -or $path -eq "/") {
                $path = "/index.html"
            }
            
            # Map request to local file in the same directory
            $currentDir = $PSScriptRoot
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

