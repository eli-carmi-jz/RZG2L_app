param(
  [string]$Port = "COM12",
  [Parameter(Mandatory)][string]$Cmd,
  [int]$WaitMs = 3000,
  [int]$IdleMs = 600
)
# Runs one shell command on the board console and prints the output.
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, "None", 8, "One"
$sp.Open()
try {
  $sp.DiscardInBuffer()
  $sp.Write("`r"); Start-Sleep -Milliseconds 200
  $sp.DiscardInBuffer()
  $sp.Write($Cmd + "`r")
  $end = (Get-Date).AddMilliseconds($WaitMs)
  $sb = New-Object System.Text.StringBuilder
  while ((Get-Date) -lt $end) {
    if ($sp.BytesToRead -gt 0) { [void]$sb.Append($sp.ReadExisting()); $end = (Get-Date).AddMilliseconds($IdleMs) }
    else { Start-Sleep -Milliseconds 30 }
  }
  $sb.ToString()
} finally { $sp.Close() }
