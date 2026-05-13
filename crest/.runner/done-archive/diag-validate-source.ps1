$ErrorActionPreference = 'Continue'
$path = 'C:\Users\Steve\.nuget\packages\bannerlord.butr.shared\3.0.0.142\content\cs\netstandard2.0\Bannerlord.BUTR.Shared\Helpers\ModuleInfoHelper.cs'
if (-not (Test-Path $path)) {
    Write-Host "Not found: $path"
    Get-ChildItem 'C:\Users\Steve\.nuget\packages\bannerlord.butr.shared' -Directory | ForEach-Object {
        Write-Host "Found version dir: $($_.Name)"
    }
    return
}
Write-Host "==> ValidateLoadOrder source (and surrounding code):"
$lines = Get-Content $path
$start = ($lines | Select-String 'ValidateLoadOrder' | Select-Object -First 1).LineNumber
if ($start) {
    $end = [Math]::Min($start + 90, $lines.Count)
    for ($i = $start - 5; $i -lt $end; $i++) {
        Write-Host ("{0,4}: {1}" -f ($i + 1), $lines[$i])
    }
}
Write-Host ""
Write-Host "==> Total file size: $((Get-Item $path).Length) bytes"
