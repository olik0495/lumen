# Lumen installer. Downloads the newest Lumen from GitHub and installs it for you (no admin needed):
#   - into %LOCALAPPDATA%\Programs\Lumen (your settings, links and data are kept when you install again)
#   - with a Start menu entry, a desktop shortcut and an entry in Settings > Apps (to uninstall)
# Run it with:   irm https://olik0495.github.io/lumen/install.ps1 | iex
# Lumen without the built-in browser:   $env:LUMEN_EDITION='plain'; irm https://olik0495.github.io/lumen/install.ps1 | iex
# Lumen is (c) olik0495, all rights reserved.

& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue' # (much faster downloads in Windows PowerShell)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  function Say($text, $color = 'Gray') { Write-Host "  $text" -ForegroundColor $color }

  try {
    Write-Host ''
    Say 'Lumen installer' 'Magenta'
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\Lumen'
    $test = [bool]$env:LUMEN_TEST_DIR # (testing: install there, without shortcuts, Settings entry or starting Lumen)
    if ($test) { $dir = $env:LUMEN_TEST_DIR }
    $plain = $env:LUMEN_EDITION -eq 'plain'

    # 1. The newest version (a local zip can be given for testing with LUMEN_ZIP).
    if ($env:LUMEN_ZIP) {
      $zipSource = $env:LUMEN_ZIP; $version = 'local'; $digest = ''
    } else {
      Say 'Looking for the newest version...'
      $rel = Invoke-RestMethod 'https://api.github.com/repos/olik0495/lumen/releases/latest' -Headers @{ 'User-Agent' = 'lumen-installer' }
      $pattern = '^Lumen-Browser-[\d.]+\.zip$'
      if ($plain) { $pattern = '^Lumen-[\d.]+\.zip$' }
      $asset = $rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
      if (-not $asset) { throw 'The Lumen download could not be found. Please try again later.' }
      $version = $rel.tag_name -replace '^v', ''
      $digest = [string]$asset.digest
    }

    # 2. Download and check it.
    $tmp = Join-Path $env:TEMP ('lumen-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'lumen.zip'
    if ($env:LUMEN_ZIP) { Copy-Item $zipSource $zip }
    else {
      Say ("Downloading Lumen $version (" + [math]::Round($asset.size / 1MB) + ' MB)...')
      Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
      # (no checksum from GitHub = nothing to check the download against: better not to install it)
      if ($digest -notlike 'sha256:*') { throw 'GitHub did not confirm the download. Please try again later.' }
      $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
      if (('sha256:' + $hash) -ne $digest.ToLower()) { throw 'The download was damaged. Please run the installer again.' }
    }

    # 3. Unpack (Windows' own tar, run inside the folder so unusual user names don't trip it up).
    Say 'Unpacking...'
    Push-Location $tmp
    try { & (Join-Path $env:SystemRoot 'System32\tar.exe') -x -f 'lumen.zip'; if ($LASTEXITCODE) { throw 'Unpacking failed.' } } finally { Pop-Location }
    $app = Get-ChildItem $tmp -Directory | ForEach-Object { Join-Path $_.FullName 'app' } | Where-Object { Test-Path (Join-Path $_ 'Lumen.exe') } | Select-Object -First 1
    if (-not $app) { throw 'The download did not contain Lumen.' }

    # 4. Close Lumen if it's open (it saves first), then swap the new version in.
    $open = @(Get-Process Lumen -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') })
    if ($open.Count) {
      Say 'Closing Lumen...'
      $open | ForEach-Object { [void]$_.CloseMainWindow() }
      for ($i = 0; $i -lt 20 -and @(Get-Process Lumen -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') }).Count; $i++) { Start-Sleep -Milliseconds 500 }
      Get-Process Lumen -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') } | Stop-Process -Force
      Start-Sleep 1
    }
    Say 'Installing...'
    New-Item -ItemType Directory -Force -Path (Split-Path $dir) | Out-Null
    $old = "$dir.old"
    if (Test-Path $old) { Remove-Item $old -Recurse -Force }
    if (Test-Path $dir) { Rename-Item $dir $old }
    try {
      try { Move-Item $app $dir -ErrorAction Stop } catch { Copy-Item $app $dir -Recurse -Force -ErrorAction Stop } # (a temp folder on another drive)
    } catch {
      if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
      if (Test-Path $old) { Rename-Item $old $dir }
      throw
    }
    if (Test-Path $old) { Remove-Item $old -Recurse -Force -ErrorAction SilentlyContinue }
    Get-ChildItem $dir -Recurse -File | Unblock-File # (no "downloaded from the internet" warnings)

    # 5. Shortcuts and the entry in Settings > Apps.
    $exe = Join-Path $dir 'Lumen.exe'
    $icon = Join-Path $dir 'resources\app\icon.ico'
    if ($test) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; Say "Test install done in $dir" 'Green'; return }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($place in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
      $s = $shell.CreateShortcut((Join-Path $place 'Lumen.lnk'))
      $s.TargetPath = $exe; $s.WorkingDirectory = $dir; $s.IconLocation = "$icon,0"; $s.Description = 'Lumen'
      $s.Save()
    }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Lumen'
    New-Item -Path $key -Force | Out-Null
    $size = [int]((Get-ChildItem $dir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
    $values = @{ DisplayName = 'Lumen'; DisplayVersion = $version; Publisher = 'olik0495'; DisplayIcon = $icon; InstallLocation = $dir;
      URLInfoAbout = 'https://olik0495.github.io/lumen'; UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\uninstall.ps1`"" }
    foreach ($k in $values.Keys) { New-ItemProperty -Path $key -Name $k -Value $values[$k] -PropertyType String -Force | Out-Null }
    foreach ($k in 'NoModify', 'NoRepair') { New-ItemProperty -Path $key -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
    New-ItemProperty -Path $key -Name EstimatedSize -Value $size -PropertyType DWord -Force | Out-Null

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Say "Lumen $version is installed. Starting it now..." 'Green'
    if (-not $env:LUMEN_NO_START) { Start-Process $exe }
    Write-Host ''
  } catch {
    Say ("Lumen couldn't be installed: " + $_.Exception.Message) 'Red'
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
  }
}
