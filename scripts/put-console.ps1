param(
  [string]$Port = "COM12",
  [Parameter(Mandatory)][string]$Src,
  [Parameter(Mandatory)][string]$Dest
)
# Copies a small file through the console as base64 lines (used only to bootstrap recv.py).
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $Src)))
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, "None", 8, "One"
$sp.Open()
try {
  $sp.Write("`r"); Start-Sleep -Milliseconds 200
  $sp.Write("stty -echo; rm -f /tmp/put.b64`r"); Start-Sleep -Milliseconds 300
  for ($i = 0; $i -lt $b64.Length; $i += 120) {
    $line = $b64.Substring($i, [Math]::Min(120, $b64.Length - $i))
    $sp.Write("echo $line >> /tmp/put.b64`r"); Start-Sleep -Milliseconds 40
  }
  $sp.Write("base64 -d /tmp/put.b64 > $Dest && chmod +x $Dest; stty echo`r")
  Start-Sleep -Milliseconds 1500
} finally { $sp.Close() }
