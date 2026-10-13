param(
  [Parameter(Mandatory)][string]$Src,
  [string]$Name = "",
  [string]$Console = "COM12",
  [string]$Data = "COM14"
)
# Copies a file to /home/root/apps/<Name> over the USB serial gadget.
$here = $PSScriptRoot
if (-not $Name) { $Name = Split-Path $Src -Leaf }
$dest = "/home/root/apps/$Name"
& "$here\console.ps1" -Port $Console -Cmd 'python3 /home/root/recv.py > /tmp/recv.log 2>&1 &' -WaitMs 1500 | Out-Null
& "$here\usb-send.ps1" -Port $Data -Src $Src -Dest $dest
exit $LASTEXITCODE
