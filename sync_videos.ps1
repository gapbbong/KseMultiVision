param(
    [string]$folderId,
    [string]$accessToken
)

if ([string]::IsNullOrEmpty($folderId) -or [string]::IsNullOrEmpty($accessToken)) {
    Write-Host "Error: folderId and accessToken are required."
    exit
}

$videosDir = "C:\Videos"
if (-not (Test-Path $videosDir)) {
    New-Item -Path $videosDir -ItemType Directory -Force | Out-Null
}

try {
    # 1. Get the list of videos in the folder
    $url = "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents+and+mimeType+contains+'video/'&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true"
    
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $wc.Headers.Add("Authorization", "Bearer $accessToken")
    
    Write-Host "Fetching video list for folder: $folderId"
    $jsonBytes = $wc.DownloadData($url)
    $jsonStr = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
    
    # Simple parse without external JSON parser dependencies (just in case) using ConvertFrom-Json
    $data = ConvertFrom-Json $jsonStr
    if ($data -and $data.files) {
        $activeIds = @()
        foreach ($file in $data.files) {
            $id = $file.id
            $name = $file.name
            $activeIds += $id
            
            $localPath = Join-Path $videosDir "$id.mp4"
            $tmpPath = Join-Path $videosDir "$id.mp4.tmp"
            
            if (-not (Test-Path $localPath)) {
                Write-Host "Downloading $name ($id) to $localPath"
                
                try {
                    $dlUrl = "https://www.googleapis.com/drive/v3/files/$id`?alt=media&supportsAllDrives=true"
                    $dlWc = New-Object System.Net.WebClient
                    $dlWc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $dlWc.Headers.Add("Authorization", "Bearer $accessToken")
                    
                    # Download file asynchronously or synchronously
                    $dlWc.DownloadFile($dlUrl, $tmpPath)
                    
                    if (Test-Path $tmpPath) {
                        Rename-Item -Path $tmpPath -NewName "$id.mp4" -Force
                        Write-Host "Successfully downloaded $name"
                    }
                } catch {
                    Write-Host "Failed to download $name : $_"
                    if (Test-Path $tmpPath) {
                        Remove-Item -Path $tmpPath -Force
                    }
                }
            } else {
                Write-Host "Already downloaded: $name"
            }
        }
        
        # Cleanup files that are not in activeIds (except debug_list.json)
        # Optional: uncomment if we want to delete untracked files
        # $localFiles = Get-ChildItem -Path $videosDir -Filter "*.mp4"
        # foreach ($f in $localFiles) {
        #     $fileId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        #     if ($activeIds -notcontains $fileId) {
        #         Write-Host "Cleaning up removed file: $($f.Name)"
        #         Remove-Item -Path $f.FullName -Force
        #     }
        # }
    }
} catch {
    Write-Host "Error in sync_videos.ps1: $_"
}
