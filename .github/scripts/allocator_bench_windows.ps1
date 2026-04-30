$tokioOn = $env:TOKIO_MULTI_THREAD
$tokioFeature = if ($tokioOn -eq "true") { "tokio-multi-thread" } else { "" }

$allocators = @("system", "mimalloc_v2", "mimalloc_v3")

function Build-Features([string]$allocator, [string]$tokio) {
  $features = @()
  if ($allocator -ne "system") { $features += $allocator }
  if ($tokio) { $features += $tokio }
  return ($features -join ",")
}

function Run-One([string]$allocator, [string]$features) {
  $args = @("build", "--release", "--locked")
  if ($features) { $args += "--features"; $args += $features }

  $proc = Start-Process -FilePath "cargo" -ArgumentList $args -PassThru -NoNewWindow -Wait

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
      if ($p.PageFaults -gt $faults) { $faults = $p.PageFaults }
    } catch { }
  }

  $peakKb = [math]::Floor($peak / 1kb)
  Add-Content -Path results.tsv -Value "$allocator`t$peakKb`t$faults"
}

if (Test-Path results.tsv) { Remove-Item results.tsv -Force }
foreach ($allocator in $allocators) {
  $features = Build-Features $allocator $tokioFeature
  Run-One $allocator $features
}

$summary = @()
$summary += "### $($env:PLATFORM_LABEL) (tokio-multi-thread=$tokioOn)"
$summary += ""
$summary += "| Allocator | Peak KB | Page Faults |"
$summary += "| --- | ---: | ---: |"

Get-Content results.tsv | ForEach-Object {
  $parts = $_ -split "`t"
  $summary += "| $($parts[0]) | $($parts[1]) | $($parts[2]) |"
}
$summary += ""
$summary -join "`n" | Add-Content $env:GITHUB_STEP_SUMMARY
