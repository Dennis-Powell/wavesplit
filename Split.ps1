#
# PowerShell Script: Automatisches Splitting von WAV-Dateien mit Config (OPTIMIERT)
# 
# Das Script durchsucht alle Unterordner in "h:\X_LIVE" und splittet WAV-Dateien
# in 32 Kanäle auf. Eine Datei wird nur gesplittet, wenn der Ordner nur eine WAV-Datei enthält.
# Channel-Namen und Skip-Logik werden aus split.cfg gelesen.
#
# OPTIMIERUNGEN:
# - Parallele Verarbeitung von Ordnern (PowerShell 5.1 und 7+ kompatibel)
# - Batch-Processing für ffmpeg 7+ (alle Kanäle in einem Durchlauf)
# - Optimierte ffmpeg Parameter
# - Optionales Präfix basierend auf Ordnernamen
#
# Requirements: ffmpeg und ffprobe müssen installiert und in PATH verfügbar sein.
#

# ===== KONFIGURATION =====
$configFile = Join-Path $PSScriptRoot "split.cfg"

# ===== FUNCTIONS =====

function Parse-ConfigFile {
    param([string]$filePath)
    
    $config = @{
        Channels = @{}
        Options = @{}
    }
    
    if (-not (Test-Path $filePath)) {
        Write-Host "Warnung: Config-Datei nicht gefunden: $filePath" -ForegroundColor Yellow
        return $config
    }
    
    $lines = Get-Content $filePath
    $currentSection = $null
    
    foreach ($line in $lines) {
        $line = $line.Trim()
        
        # Kommentare und leere Zeilen überspringen
        if ($line.StartsWith("#") -or $line.StartsWith(";") -or $line -eq "") {
            continue
        }
        
        # Section erkennen
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }
        
        # Key=Value Paare parsen
        if ($line -match '^(.+?)\s*=\s*(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            if ($currentSection -eq "Channels") {
                # Nur numerische Keys in Channels
                if ($key -match '^\d+$') {
                    $config.Channels[[int]$key] = $value
                }
            }
            elseif ($currentSection -eq "Options") {
                $config.Options[$key] = $value
            }
        }
    }
    
    return $config
}

function Get-ChannelName {
    param(
        [int]$channelNum,
        [hashtable]$config
    )
    
    if ($config.Channels.ContainsKey($channelNum)) {
        $name = $config.Channels[$channelNum]
        # "(Skip)" oder leere Namen bedeuten: nicht erstellen
        if ($name -eq "(Skip)" -or $name -eq "") {
            return $null
        }
        return $name
    }
    
    return $null
}

function Get-FilePrefix {
    param(
        [string]$folderName,
        [hashtable]$config
    )
    
    # Prüfe ob Ordnername als Präfix verwendet werden soll
    if ($config.Options.UseFolderNameAsPrefix -eq "true") {
        return $folderName
    } else {
        # Kein Präfix
        return ""
    }
}

function Process-WavFile {
    param(
        [string]$wavFullPath,
        [string]$outputDir,
        [hashtable]$config,
        [string]$PF,
        [bool]$verboseOutput
    )
    
    # Sample Rate ermitteln
    $ffprobeOutput = ffprobe -loglevel quiet -show_streams $wavFullPath 2>$null
    $sampleRateMatch = $ffprobeOutput | Select-String -Pattern "sample_rate=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    
    if (-not $sampleRateMatch) {
        throw "Sample Rate konnte nicht ermittelt werden"
    }
    
    $SR = $sampleRateMatch
    
    # Bit Depth ermitteln und Codec setzen
    $bitsMatch = $ffprobeOutput | Select-String -Pattern "bits_per_sample=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $sourceBits = if ($bitsMatch) { $bitsMatch } else { "32" }
    
    $confBitDepth = $config.Options.BitDepth
    if ([string]::IsNullOrWhiteSpace($confBitDepth) -or $confBitDepth -eq "auto") {
        $targetBits = $sourceBits
    } else {
        $targetBits = $confBitDepth
    }
    
    switch ($targetBits) {
        "16" { $codec = "pcm_s16le" }
        "24" { $codec = "pcm_s24le" }
        "32" { $codec = "pcm_s32le" }
        default { 
            $codec = "pcm_s32le" 
        }
    }
    
    # ffmpeg Version prüfen
    $ffmpegVersionOutput = ffmpeg -version 2>$null | Select-Object -First 1
    $ffmpegVersion = $ffmpegVersionOutput | Select-String -Pattern "ffmpeg version ([\d.]+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $ffmpegMajorVersion = [int]($ffmpegVersion.Split('.')[0])
    
    Push-Location $outputDir
    
    if ($ffmpegMajorVersion -ge 7) {
        # ===== OPTIMIERUNG FÜR FFmpeg 7+: BATCH PROCESSING =====
        # Alle Kanäle in einem einzigen ffmpeg-Aufruf verarbeiten
        
        $ffmpegArgs = @(
            "-loglevel", "error",
            "-i", $wavFullPath
        )
        
        $filterParts = @()
        
        for ($i = 0; $i -lt 32; $i++) {
            $channelIndex = $i
            $outputNum = $i + 1
            
            # Channel-Namen ermitteln
            $channelName = Get-ChannelName -ChannelNum $outputNum -Config $config
            
            # Skip diesen Kanal wenn kein Name definiert
            if ($null -eq $channelName) {
                continue
            }
            
            # Output-Dateiname mit oder ohne Präfix
            if ($PF -eq "") {
                $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
            } else {
                $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
            }
            
            # Filter für diesen Kanal
            $filterParts += "[0]pan=mono|c0=c$channelIndex[out$outputNum]"
            
            # Map und Output
            $ffmpegArgs += @("-map", "[out$outputNum]")
            $ffmpegArgs += @("-ar", $SR, "-acodec", $codec)
            $ffmpegArgs += $outputFile
        }
        
        # Nur verarbeiten wenn es Kanäle gibt
        if ($filterParts.Count -gt 0) {
            # Filter Complex zusammenbauen
            $filterComplex = $filterParts -join ";"
            
            # Filter Complex einfügen (nach -i Parameter)
            $ffmpegArgsFinal = @(
                "-loglevel", "error",
                "-i", $wavFullPath,
                "-filter_complex", $filterComplex
            ) + $ffmpegArgs[4..($ffmpegArgs.Count - 1)]
            
            & ffmpeg @ffmpegArgsFinal
            
            if ($LASTEXITCODE -ne 0) {
                throw "ffmpeg Batch-Fehler (Exit Code: $LASTEXITCODE)"
            }
        }
        
    } else {
        # FFmpeg 6 und älter - mit map_channel (einzelne Aufrufe)
        $ffmpegArgs = @(
            "-loglevel", "error",
            "-i", $wavFullPath
        )
        
        for ($i = 0; $i -lt 32; $i++) {
            $outputNum = $i + 1
            $channelName = Get-ChannelName -ChannelNum $outputNum -Config $config
            
            # Bei leeren Namen default Name ausgeben
            if ($null -eq $channelName) {
                if ($PF -eq "") {
                    $outputFile = "{0:D2}.wav" -f $outputNum
                } else {
                    $outputFile = "{0}-{1:D2}.wav" -f $PF, $outputNum
                }
            } else {
                if ($PF -eq "") {
                    $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
                } else {
                    $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
                }
            }
            
            $ffmpegArgs += @(
                "-ar", $SR,
                "-acodec", $codec,
                "-map_channel", "0.0.$i",
                $outputFile
            )
        }
        
        & ffmpeg @ffmpegArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg Fehler beim Splitting (Exit Code: $LASTEXITCODE)"
        }
    }
    
    Pop-Location
}

# ===== HAUPTSKRIPT =====

# Config laden
$config = Parse-ConfigFile -FilePath $configFile

# BasePath aus Config lesen
$basePathConfig = $config.Options["BasePath"]
if ([string]::IsNullOrWhiteSpace($basePathConfig)) {
    throw "BasePath wurde in der Config-Datei nicht definiert."
}

if ([System.IO.Path]::IsPathRooted($basePathConfig)) {
    $basePath = $basePathConfig
} else {
    $basePath = Join-Path $PSScriptRoot $basePathConfig
}

# Parallel Processing aktivieren? (Standard: ja, falls mehr als 1 Ordner)
$useParallel = $true
if ($config.Options.ParallelProcessing -eq "false") {
    $useParallel = $false
}

# Maximale parallele Jobs (Standard: Anzahl CPU Kerne)
$maxParallelJobs = [Environment]::ProcessorCount
if ($config.Options.MaxParallelJobs) {
    $maxParallelJobs = [int]$config.Options.MaxParallelJobs
}

$psVersion = $PSVersionTable.PSVersion.Major

Write-Host "================================" -ForegroundColor Cyan
Write-Host "WAV-Splitting Script gestartet (OPTIMIERT)" -ForegroundColor Cyan
Write-Host "PowerShell Version: $psVersion" -ForegroundColor Cyan
Write-Host "Basis-Pfad: $basePath" -ForegroundColor Cyan
Write-Host "Config-Datei: $configFile" -ForegroundColor Cyan
Write-Host "Parallel-Verarbeitung: $useParallel (Max: $maxParallelJobs Jobs)" -ForegroundColor Cyan
Write-Host "Ordnername als Praefix: $($config.Options.UseFolderNameAsPrefix)" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Statistik-Variablen
$processedCount = 0
$skippedCount = 0
$errorCount = 0

# Schleife durch alle Unterordner in X_LIVE
$folders = Get-ChildItem -Path $basePath -Directory | Sort-Object Name

# Nur Ordner mit genau 1 WAV-Datei sammeln
$foldersToProcess = @()

foreach ($folder in $folders) {
    $wavFiles = @(Get-ChildItem -Path $folder.FullName -Filter "*.wav" -File)
    $wavCount = $wavFiles.Count
    
    if ($wavCount -eq 0) {
        Write-Host "Ueberspringe: $($folder.Name) - Keine WAV-Dateien" -ForegroundColor Gray
        $skippedCount++
    }
    elseif ($wavCount -gt 1) {
        Write-Host "Ueberspringe: $($folder.Name) - $wavCount WAV-Dateien (bereits gesplittet?)" -ForegroundColor Gray
        $skippedCount++
    }
    else {
        $foldersToProcess += $folder
    }
}

Write-Host ""
Write-Host "Zu verarbeitende Ordner: $($foldersToProcess.Count)" -ForegroundColor Yellow
Write-Host ""

# Zeitmessung starten
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if ($useParallel -and $foldersToProcess.Count -gt 1) {
    
    if ($psVersion -ge 7) {
        # ===== PARALLELE VERARBEITUNG FÜR PowerShell 7+ =====
        Write-Host "Starte parallele Verarbeitung (PS7+) mit max. $maxParallelJobs gleichzeitigen Jobs..." -ForegroundColor Cyan
        Write-Host ""
        
        $foldersToProcess | ForEach-Object -ThrottleLimit $maxParallelJobs -Parallel {
            $folder = $_
            $config = $using:config
            
            try {
                $wavFile = @(Get-ChildItem -Path $folder.FullName -Filter "*.wav" -File)[0]
                $wavFileName = $wavFile.Name
                $wavFullPath = $wavFile.FullName
                
                # Präfix ermitteln (Ordnername oder kein Präfix)
                if ($config.Options.UseFolderNameAsPrefix -eq "true") {
                    $PF = $folder.Name
                } else {
                    $PF = ""
                }
                
                # Subfolder erstellen wenn konfiguriert
                $outputDir = $folder.FullName
                if ($config.Options.CreateSubfolderForChannels -eq "true") {
                    $outputDir = Join-Path $folder.FullName "channels"
                    if (-not (Test-Path $outputDir)) {
                        New-Item -ItemType Directory -Path $outputDir | Out-Null
                    }
                }
                
                $prefixInfo = if ($PF -eq "") { "kein Praefix" } else { "Praefix: $PF" }
                Write-Host "[Processing] $($folder.Name) - $wavFileName ($prefixInfo)" -ForegroundColor Green
                
                # Process-WavFile Inline (da Functions nicht in Parallel-Block übertragen werden)
                $ffprobeOutput = ffprobe -loglevel quiet -show_streams $wavFullPath 2>$null
                $sampleRateMatch = $ffprobeOutput | Select-String -Pattern "sample_rate=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                
                if (-not $sampleRateMatch) {
                    throw "Sample Rate konnte nicht ermittelt werden"
                }
                
                $SR = $sampleRateMatch
                
                $bitsMatch = $ffprobeOutput | Select-String -Pattern "bits_per_sample=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                $sourceBits = if ($bitsMatch) { $bitsMatch } else { "32" }
                
                $confBitDepth = $config.Options.BitDepth
                if ([string]::IsNullOrWhiteSpace($confBitDepth) -or $confBitDepth -eq "auto") {
                    $targetBits = $sourceBits
                } else {
                    $targetBits = $confBitDepth
                }
                
                switch ($targetBits) {
                    "16" { $codec = "pcm_s16le" }
                    "24" { $codec = "pcm_s24le" }
                    "32" { $codec = "pcm_s32le" }
                    default { $codec = "pcm_s32le" }
                }
                
                $ffmpegVersionOutput = ffmpeg -version 2>$null | Select-Object -First 1
                $ffmpegVersion = $ffmpegVersionOutput | Select-String -Pattern "ffmpeg version ([\d.]+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                $ffmpegMajorVersion = [int]($ffmpegVersion.Split('.')[0])
                
                Push-Location $outputDir
                
                if ($ffmpegMajorVersion -ge 7) {
                    # Batch Processing für ffmpeg 7+
                    $ffmpegArgs = @("-loglevel", "error", "-i", $wavFullPath)
                    $filterParts = @()
                    
                    for ($i = 0; $i -lt 32; $i++) {
                        $outputNum = $i + 1
                        $channelName = $null
                        
                        if ($config.Channels.ContainsKey($outputNum)) {
                            $name = $config.Channels[$outputNum]
                            if ($name -ne "(Skip)" -and $name -ne "") {
                                $channelName = $name
                            }
                        }
                        
                        if ($null -eq $channelName) { continue }
                        
                        if ($PF -eq "") {
                            $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
                        } else {
                            $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
                        }
                        
                        $filterParts += "[0]pan=mono|c0=c$i[out$outputNum]"
                        $ffmpegArgs += @("-map", "[out$outputNum]", "-ar", $SR, "-acodec", $codec, $outputFile)
                    }
                    
                    if ($filterParts.Count -gt 0) {
                        $filterComplex = $filterParts -join ";"
                        $ffmpegArgsFinal = @("-loglevel", "error", "-i", $wavFullPath, "-filter_complex", $filterComplex) + $ffmpegArgs[4..($ffmpegArgs.Count - 1)]
                        & ffmpeg @ffmpegArgsFinal
                        
                        if ($LASTEXITCODE -ne 0) {
                            throw "ffmpeg Batch-Fehler (Exit Code: $LASTEXITCODE)"
                        }
                    }
                } else {
                    # ffmpeg 6 Methode
                    $ffmpegArgs = @("-loglevel", "error", "-i", $wavFullPath)
                    
                    for ($i = 0; $i -lt 32; $i++) {
                        $outputNum = $i + 1
                        $channelName = $null
                        
                        if ($config.Channels.ContainsKey($outputNum)) {
                            $name = $config.Channels[$outputNum]
                            if ($name -ne "(Skip)" -and $name -ne "") {
                                $channelName = $name
                            }
                        }
                        
                        if ($null -eq $channelName) {
                            if ($PF -eq "") {
                                $outputFile = "{0:D2}.wav" -f $outputNum
                            } else {
                                $outputFile = "{0}-{1:D2}.wav" -f $PF, $outputNum
                            }
                        } else {
                            if ($PF -eq "") {
                                $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
                            } else {
                                $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
                            }
                        }
                        
                        $ffmpegArgs += @("-ar", $SR, "-acodec", $codec, "-map_channel", "0.0.$i", $outputFile)
                    }
                    
                    & ffmpeg @ffmpegArgs
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "ffmpeg Fehler (Exit Code: $LASTEXITCODE)"
                    }
                }
                
                Pop-Location
                
                Write-Host "[OK Fertig] $($folder.Name)" -ForegroundColor Green
                
            } catch {
                Write-Host "[XX FEHLER] $($folder.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        $processedCount = $foldersToProcess.Count
        
    } else {
        # ===== PARALLELE VERARBEITUNG FÜR PowerShell 5.1 mit Start-Job =====
        Write-Host "Starte parallele Verarbeitung (PS5.1) mit max. $maxParallelJobs gleichzeitigen Jobs..." -ForegroundColor Cyan
        Write-Host ""
        
        $jobs = @()
        $completedCount = 0
        $totalCount = $foldersToProcess.Count
        
        # ScriptBlock für die Job-Verarbeitung
        $scriptBlock = {
            param($folder, $configFile, $PSScriptRoot)
            
            # Config neu laden im Job-Kontext
            function Parse-ConfigFile {
                param([string]$filePath)
                
                $config = @{
                    Channels = @{}
                    Options = @{}
                }
                
                if (-not (Test-Path $filePath)) {
                    return $config
                }
                
                $lines = Get-Content $filePath
                $currentSection = $null
                
                foreach ($line in $lines) {
                    $line = $line.Trim()
                    
                    if ($line.StartsWith("#") -or $line.StartsWith(";") -or $line -eq "") {
                        continue
                    }
                    
                    if ($line -match '^\[(.+)\]$') {
                        $currentSection = $matches[1]
                        continue
                    }
                    
                    if ($line -match '^(.+?)\s*=\s*(.*)$') {
                        $key = $matches[1].Trim()
                        $value = $matches[2].Trim()
                        
                        if ($currentSection -eq "Channels") {
                            if ($key -match '^\d+$') {
                                $config.Channels[[int]$key] = $value
                            }
                        }
                        elseif ($currentSection -eq "Options") {
                            $config.Options[$key] = $value
                        }
                    }
                }
                
                return $config
            }
            
            $config = Parse-ConfigFile -FilePath $configFile
            
            try {
                $wavFile = @(Get-ChildItem -Path $folder.FullName -Filter "*.wav" -File)[0]
                $wavFileName = $wavFile.Name
                $wavFullPath = $wavFile.FullName
                
                # Präfix ermitteln (Ordnername oder kein Präfix)
                if ($config.Options.UseFolderNameAsPrefix -eq "true") {
                    $PF = $folder.Name
                } else {
                    $PF = ""
                }
                
                $outputDir = $folder.FullName
                if ($config.Options.CreateSubfolderForChannels -eq "true") {
                    $outputDir = Join-Path $folder.FullName "channels"
                    if (-not (Test-Path $outputDir)) {
                        New-Item -ItemType Directory -Path $outputDir | Out-Null
                    }
                }
                
                $ffprobeOutput = ffprobe -loglevel quiet -show_streams $wavFullPath 2>$null
                $sampleRateMatch = $ffprobeOutput | Select-String -Pattern "sample_rate=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                
                if (-not $sampleRateMatch) {
                    throw "Sample Rate konnte nicht ermittelt werden"
                }
                
                $SR = $sampleRateMatch
                
                $bitsMatch = $ffprobeOutput | Select-String -Pattern "bits_per_sample=(\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                $sourceBits = if ($bitsMatch) { $bitsMatch } else { "32" }
                
                $confBitDepth = $config.Options.BitDepth
                if ([string]::IsNullOrWhiteSpace($confBitDepth) -or $confBitDepth -eq "auto") {
                    $targetBits = $sourceBits
                } else {
                    $targetBits = $confBitDepth
                }
                
                switch ($targetBits) {
                    "16" { $codec = "pcm_s16le" }
                    "24" { $codec = "pcm_s24le" }
                    "32" { $codec = "pcm_s32le" }
                    default { $codec = "pcm_s32le" }
                }
                
                $ffmpegVersionOutput = ffmpeg -version 2>$null | Select-Object -First 1
                $ffmpegVersion = $ffmpegVersionOutput | Select-String -Pattern "ffmpeg version ([\d.]+)" | ForEach-Object { $_.Matches.Groups[1].Value }
                $ffmpegMajorVersion = [int]($ffmpegVersion.Split('.')[0])
                
                Push-Location $outputDir
                
                if ($ffmpegMajorVersion -ge 7) {
                    $ffmpegArgs = @("-loglevel", "error", "-i", $wavFullPath)
                    $filterParts = @()
                    
                    for ($i = 0; $i -lt 32; $i++) {
                        $outputNum = $i + 1
                        $channelName = $null
                        
                        if ($config.Channels.ContainsKey($outputNum)) {
                            $name = $config.Channels[$outputNum]
                            if ($name -ne "(Skip)" -and $name -ne "") {
                                $channelName = $name
                            }
                        }
                        
                        if ($null -eq $channelName) { continue }
                        
                        if ($PF -eq "") {
                            $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
                        } else {
                            $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
                        }
                        
                        $filterParts += "[0]pan=mono|c0=c$i[out$outputNum]"
                        $ffmpegArgs += @("-map", "[out$outputNum]", "-ar", $SR, "-acodec", $codec, $outputFile)
                    }
                    
                    if ($filterParts.Count -gt 0) {
                        $filterComplex = $filterParts -join ";"
                        $ffmpegArgsFinal = @("-loglevel", "error", "-i", $wavFullPath, "-filter_complex", $filterComplex) + $ffmpegArgs[4..($ffmpegArgs.Count - 1)]
                        & ffmpeg @ffmpegArgsFinal
                        
                        if ($LASTEXITCODE -ne 0) {
                            throw "ffmpeg Batch-Fehler (Exit Code: $LASTEXITCODE)"
                        }
                    }
                } else {
                    $ffmpegArgs = @("-loglevel", "error", "-i", $wavFullPath)
                    
                    for ($i = 0; $i -lt 32; $i++) {
                        $outputNum = $i + 1
                        $channelName = $null
                        
                        if ($config.Channels.ContainsKey($outputNum)) {
                            $name = $config.Channels[$outputNum]
                            if ($name -ne "(Skip)" -and $name -ne "") {
                                $channelName = $name
                            }
                        }
                        
                        if ($null -eq $channelName) {
                            if ($PF -eq "") {
                                $outputFile = "{0:D2}.wav" -f $outputNum
                            } else {
                                $outputFile = "{0}-{1:D2}.wav" -f $PF, $outputNum
                            }
                        } else {
                            if ($PF -eq "") {
                                $outputFile = "{0:D2} {1}.wav" -f $outputNum, $channelName
                            } else {
                                $outputFile = "{0}-{1:D2} {2}.wav" -f $PF, $outputNum, $channelName
                            }
                        }
                        
                        $ffmpegArgs += @("-ar", $SR, "-acodec", $codec, "-map_channel", "0.0.$i", $outputFile)
                    }
                    
                    & ffmpeg @ffmpegArgs
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "ffmpeg Fehler (Exit Code: $LASTEXITCODE)"
                    }
                }
                
                Pop-Location
                
                return @{
                    Success = $true
                    FolderName = $folder.Name
                    FileName = $wavFileName
                    Prefix = if ($PF -eq "") { "kein Praefix" } else { $PF }
                }
                
            } catch {
                return @{
                    Success = $false
                    FolderName = $folder.Name
                    Error = $_.Exception.Message
                }
            }
        }
        
        # Jobs starten
        foreach ($folder in $foldersToProcess) {
            # Warte wenn maximale Anzahl Jobs erreicht
            while ((Get-Job -State Running).Count -ge $maxParallelJobs) {
                Start-Sleep -Milliseconds 100
                
                # Prüfe auf fertige Jobs
                $finishedJobs = Get-Job -State Completed
                foreach ($job in $finishedJobs) {
                    $result = Receive-Job -Job $job
                    if ($result.Success) {
                        Write-Host "[OK] $($result.FolderName) - $($result.FileName) ($($result.Prefix))" -ForegroundColor Green
                        $processedCount++
                    } else {
                        Write-Host "[XX FEHLER] $($result.FolderName): $($result.Error)" -ForegroundColor Red
                        $errorCount++
                    }
                    Remove-Job -Job $job
                    $completedCount++
                }
            }
            
            # Neuen Job starten
            $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $folder, $configFile, $PSScriptRoot
            $jobs += $job
            Write-Host "Gestartet: $($folder.Name)" -ForegroundColor Yellow
        }
        
        # Warte auf alle verbleibenden Jobs
        Write-Host ""
        Write-Host "Warte auf Abschluss aller Jobs..." -ForegroundColor Cyan
        
        while ((Get-Job -State Running).Count -gt 0) {
            Start-Sleep -Milliseconds 500
            
            $finishedJobs = Get-Job -State Completed
            foreach ($job in $finishedJobs) {
                $result = Receive-Job -Job $job
                if ($result.Success) {
                    Write-Host "[OK] $($result.FolderName) - $($result.FileName) ($($result.Prefix))" -ForegroundColor Green
                    $processedCount++
                } else {
                    Write-Host "[XX FEHLER] $($result.FolderName): $($result.Error)" -ForegroundColor Red
                    $errorCount++
                }
                Remove-Job -Job $job
                $completedCount++
            }
            
            $runningCount = (Get-Job -State Running).Count
            if ($runningCount -gt 0) {
                Write-Host "Verarbeitung laeuft: $completedCount/$totalCount abgeschlossen, $runningCount aktiv..." -ForegroundColor Gray
            }
        }
        
        # Aufräumen
        Get-Job | Remove-Job -Force
    }
    
} else {
    # ===== SEQUENTIELLE VERARBEITUNG =====
    if ($useParallel -and $foldersToProcess.Count -gt 1) {
        Write-Host "Hinweis: Nur 1 Ordner zu verarbeiten - sequentielle Verarbeitung wird verwendet." -ForegroundColor Yellow
    }
    
    foreach ($folder in $foldersToProcess) {
        Write-Host "Verarbeite Ordner: $($folder.Name)" -ForegroundColor Yellow
        
        try {
            $wavFile = @(Get-ChildItem -Path $folder.FullName -Filter "*.wav" -File)[0]
            $wavFileName = $wavFile.Name
            $wavFullPath = $wavFile.FullName
            
            Write-Host "  -> Processing: $wavFileName" -ForegroundColor Green
            
            # Präfix ermitteln (Ordnername oder kein Präfix)
            $PF = Get-FilePrefix -folderName $folder.Name -config $config
            
            if ($PF -eq "") {
                Write-Host "  -> Kein Praefix" -ForegroundColor Cyan
            } else {
                Write-Host "  -> Praefix: $PF" -ForegroundColor Cyan
            }
            
            # Subfolder erstellen wenn konfiguriert
            $outputDir = $folder.FullName
            if ($config.Options.CreateSubfolderForChannels -eq "true") {
                $outputDir = Join-Path $folder.FullName "channels"
                if (-not (Test-Path $outputDir)) {
                    New-Item -ItemType Directory -Path $outputDir | Out-Null
                }
            }
            
            Process-WavFile -wavFullPath $wavFullPath -outputDir $outputDir -config $config -PF $PF -verboseOutput ($config.Options.VerboseOutput -eq "true")
            
            Write-Host "    OK Erfolgreich abgeschlossen" -ForegroundColor Green
            $processedCount++
            
        } catch {
            Write-Host "    XX FEHLER: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host ""
    }
}

$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Zusammenfassung:" -ForegroundColor Cyan
Write-Host "  Verarbeitet: $processedCount" -ForegroundColor Green
Write-Host "  Uebersprungen: $skippedCount" -ForegroundColor Yellow
Write-Host "  Fehler: $errorCount" -ForegroundColor Red
Write-Host "  Dauer: $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan