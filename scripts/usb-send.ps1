param(
  [string]$Port = "COM14",
  [Parameter(Mandatory)][string]$Src,
  [Parameter(Mandatory)][string]$Dest
)
# Sends a file to the board's recv.py over the USB serial gadget and verifies the SHA-256.
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $Src))
$local = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)) -replace '-', '').ToLower()
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, "None", 8, "One"
$sp.WriteTimeout = 20000; $sp.ReadTimeout = 20000; $sp.DtrEnable = $true; $sp.RtsEnable = $true
$sp.Open()
try {
  $sp.DiscardInBuffer()
  $hdr = [Text.Encoding]::ASCII.GetBytes("SIZE $($bytes.Length) $Dest`n")
  $sp.Write($hdr, 0, $hdr.Length)
  for ($i = 0; $i -lt $bytes.Length; $i += 4096) {
    $n = [Math]::Min(4096, $bytes.Length - $i)
    $sp.Write($bytes, $i, $n)
  }
  $reply = $sp.ReadLine().Trim()
} finally { $sp.Close() }
if ($reply -eq "OK $local") { "sent $($bytes.Length) bytes, sha256 ok" } else { Write-Error "transfer failed: $reply (expected $local)"; exit 1 }
