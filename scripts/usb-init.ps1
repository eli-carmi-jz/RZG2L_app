param(
  [string]$Console = "COM12"
)
# Prepares the board USB serial gadget (g_serial -> /dev/ttyGS0) and installs recv.py if missing.
$here = $PSScriptRoot
$cmd = 'for p in $(ps | grep -E "[g]dbserver|[r]ecv.py" | awk "{print \$1}"); do kill $p; done; ' +
       'lsmod | grep -q g_ether && rmmod g_ether; lsmod | grep -q g_serial || modprobe g_serial; sleep 1; ' +
       'stty -F /dev/ttyGS0 raw -echo -ixon -ixoff -crtscts; ' +
       '[ -x /home/root/recv.py ] && echo R$(echo E)CV_OK || echo R$(echo E)CV_MISSING; ' +
       'cat /sys/class/udc/11c60000.usb/state'
$out = & "$here\console.ps1" -Port $Console -Cmd $cmd -WaitMs 6000 -IdleMs 2500
$out
if ($out -notmatch "(?m)^configured") { Write-Error "USB gadget not connected: plug the micro-USB cable into the PC"; exit 1 }
if ($out -match "(?m)^RECV_MISSING") {
  & "$here\put-console.ps1" -Port $Console -Src "$here\recv.py" -Dest /home/root/recv.py
  "recv.py installed on the board"
}
