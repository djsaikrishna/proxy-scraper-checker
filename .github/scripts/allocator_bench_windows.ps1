$tokioOn = $env:TOKIO_MULTI_THREAD
$tokioFeature = if ($tokioOn -eq "true") { "tokio-multi-thread" } else { "" }

$allocator = $env:ALLOCATOR
$features = @()
if ($allocator -ne "system") { $features += $allocator }
if ($tokioFeature) { $features += $tokioFeature }
$featuresString = $features -join ","

$args = @("build", "--release", "--locked")
if ($featuresString) { $args += "--features"; $args += $featuresString }

Start-Process -FilePath "cargo" -ArgumentList $args -NoNewWindow -Wait

$exe = "target\release\proxy-scraper-checker.exe"
$proc = Start-Process -FilePath $exe -PassThru -NoNewWindow

$peak = 0
$faults = 0

while (-not $proc.HasExited) {
  Start-Sleep -Milliseconds 100
  try {
    $p = Get-Process -Id $proc.Id -ErrorAction Stop
    $current = [math]::Max($p.WorkingSet64, $p.PeakWorkingSet64)
    if ($current -gt $peak) { $peak = $current }

    $wmi = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
    if ($wmi -and $wmi.PageFaults -gt $faults) { $faults = $wmi.PageFaults }
  } catch { }
}

$peakKb = [math]::Floor($peak / 1kb)
if (Test-Path results.tsv) { Remove-Item results.tsv -Force }
Add-Content -Path results.tsv -Value "$allocator`t$peakKb`t$faults"

$summary = @()
$summary += "### $($env:PLATFORM_LABEL) (tokio-multi-thread=$tokioOn, allocator=$allocator)"
$summary += "Threads: $($env:NUMBER_OF_PROCESSORS)"
$summary += ""
$summary += "| Allocator | Peak KB | Page Faults |"
$summary += "| --- | ---: | ---: |"

Get-Content results.tsv | ForEach-Object {
  $parts = $_ -split "`t"
  $summary += "| $($parts[0]) | $($parts[1]) | $($parts[2]) |"
}
$summary += ""
$summary -join "`n" | Add-Content $env:GITHUB_STEP_SUMMARY
