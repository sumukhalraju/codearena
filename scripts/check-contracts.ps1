$ErrorActionPreference = "Stop"

# Run from the parent repository root.
# Each child vendors contracts/ when implementation starts.
# Until those copies exist, this script reports that and exits 0.
# Once a copy exists, it must match the parent byte for byte.

$files = @(
  "constants.json",
  "schema.sql",
  "openapi.yaml",
  "problem-pack.example.json"
)

$failed = $false

foreach ($child in @("frontend", "backend")) {
  $dest = Join-Path $child "contracts"
  if (-not (Test-Path $dest)) {
    Write-Host "$child has not vendored contracts yet."
    continue
  }

  foreach ($file in $files) {
    $from = Join-Path "contracts" $file
    $to = Join-Path $dest $file
    if (-not (Test-Path $to)) {
      Write-Host "MISSING $to"
      $failed = $true
      continue
    }
    $a = Get-FileHash $from -Algorithm SHA256
    $b = Get-FileHash $to -Algorithm SHA256
    if ($a.Hash -ne $b.Hash) {
      Write-Host "DRIFT $to"
      $failed = $true
    } else {
      Write-Host "ok $to"
    }
  }
}

if ($failed) {
  exit 1
}
