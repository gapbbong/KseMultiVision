param(
    [string]$folderId,
    [string]$accessToken,
    [string]$keepIds,
    [string]$folderName
)

if ([string]::IsNullOrEmpty($folderId) -or [string]::IsNullOrEmpty($accessToken)) {
    Write-Host "Error: folderId and accessToken are required."
    exit
}

$targetFolder = if ([string]::IsNullOrEmpty($folderName)) {
    $folderId
} elseif ($folderName -eq $folderId) {
    $folderId
} else {
    "${folderName}_${folderId}"
}
$videosDir = Join-Path "C:\Videos" $targetFolder
if (-not (Test-Path $videosDir)) {
    New-Item -Path $videosDir -ItemType Directory -Force | Out-Null
}

try {
    # 1. Get the list of videos in the folder (or query specific ids if keepIds is specified)
    if (-not [string]::IsNullOrEmpty($keepIds)) {
        $ids = $keepIds.Split(",")
        $qParts = @()
        foreach ($id in $ids) {
            $qParts += "id = '$id'"
        }
        $q = $qParts -join " or "
        $url = "https://www.googleapis.com/drive/v3/files?q=" + [Uri]::EscapeDataString($q) + "&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true"
    } else {
        $url = "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents+and+mimeType+contains+'video/'&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true"
    }
    
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    $wc.Headers.Add("Authorization", "Bearer $accessToken")
    
    Write-Host "Fetching video list for folder: $folderId / keepIds: $keepIds"
    $jsonBytes = $wc.DownloadData($url)
    $jsonStr = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
    
    $data = ConvertFrom-Json $jsonStr
    if ($data -and $data.files) {
        $allowedIds = @()
        if (-not [string]::IsNullOrEmpty($keepIds)) {
            $allowedIds = $keepIds.Split(",")
        } else {
            # If keepIds is not specified, default to downloading all active files (backward compatibility)
            foreach ($file in $data.files) {
                $allowedIds += $file.id
            }
        }
        
        # Download files that are in the allowed list
        foreach ($file in $data.files) {
            $id = $file.id
            $name = $file.name
            
            # Skip if this file is not in the allowed cache list
            if ($allowedIds -notcontains $id) {
                continue
            }
            
            $localPath = Join-Path $videosDir "$id.mp4"
            $tmpPath = Join-Path $videosDir "$id.mp4.tmp"
            
            if (-not (Test-Path $localPath)) {
                Write-Host "Downloading $name ($id) to $localPath"
                
                try {
                    $dlUrl = "https://www.googleapis.com/drive/v3/files/$id`?alt=media&supportsAllDrives=true"
                    $dlWc = New-Object System.Net.WebClient
                    $dlWc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $dlWc.Headers.Add("Authorization", "Bearer $accessToken")
                    
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
        
        # Cleanup files that are NOT in the allowed cache list to save disk space
        $localFiles = Get-ChildItem -Path $videosDir -Filter "*.mp4"
        foreach ($f in $localFiles) {
            $fileId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($allowedIds -notcontains $fileId) {
                Write-Host "Cleaning up removed/uncached file: $($f.Name)"
                Remove-Item -Path $f.FullName -Force
            }
        }
    }
} catch {
    Write-Host "Error in sync_videos.ps1: $_"
}
