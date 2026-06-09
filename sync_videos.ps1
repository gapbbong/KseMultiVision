param(
    [string]$folderId,
    [string]$accessToken,
    [string]$keepIds,
    [string]$folderName
)

function Log-Message([string]$msg) {
    $logDir = "C:\Videos"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $logPath = Join-Path $logDir "sync_videos_script.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMsg = "[$timestamp] $msg"
    Write-Output $formattedMsg
    $formattedMsg | Out-File -FilePath $logPath -Append -Encoding utf8
}

if ([string]::IsNullOrEmpty($folderId) -or [string]::IsNullOrEmpty($accessToken)) {
    Log-Message "Error: folderId and accessToken are required."
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
    # 1. Load the list of files from the local debug JSON registry written by the Node server
    $debugListPath = Join-Path "C:\Videos" "debug_list_${folderId}.json"
    Log-Message "Loading video list from local debug registry file: $debugListPath"
    
    if (-not (Test-Path $debugListPath)) {
        throw "Debug list registry file not found at $debugListPath"
    }
    
    $jsonStr = [System.IO.File]::ReadAllText($debugListPath, [System.Text.Encoding]::UTF8)
    $data = ConvertFrom-Json $jsonStr
    
    if ($data -and $data.files) {
        $allowedIds = @()
        if (-not [string]::IsNullOrEmpty($keepIds)) {
            $allowedIds = $keepIds.Split(",")
        } else {
            # If keepIds is not specified, default to downloading all active files in the folder
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
                Log-Message "Downloading $name ($id) to $localPath"
                
                try {
                    $dlUrl = "https://www.googleapis.com/drive/v3/files/$id`?alt=media&supportsAllDrives=true"
                    $dlWc = New-Object System.Net.WebClient
                    $dlWc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $dlWc.Headers.Add("Authorization", "Bearer $accessToken")
                    
                    $dlWc.DownloadFile($dlUrl, $tmpPath)
                    
                    if (Test-Path $tmpPath) {
                        Rename-Item -Path $tmpPath -NewName "$id.mp4" -Force
                        Log-Message "Successfully downloaded $name"
                    }
                } catch {
                    Log-Message "Failed to download $name : $_"
                    if (Test-Path $tmpPath) {
                        Remove-Item -Path $tmpPath -Force
                    }
                }
            } else {
                Log-Message "Already downloaded: $name"
            }
        }
        
        # Cleanup files that are NOT in the allowed cache list to save disk space
        $localFiles = Get-ChildItem -Path $videosDir -Filter "*.mp4"
        foreach ($f in $localFiles) {
            $fileId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($allowedIds -notcontains $fileId) {
                Log-Message "Cleaning up removed/uncached file: $($f.Name)"
                Remove-Item -Path $f.FullName -Force
            }
        }
    }
} catch {
    Log-Message "Error in sync_videos.ps1: $_"
}
