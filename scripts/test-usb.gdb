set serial baud 115200
set remotetimeout 20
file hello-debug
target remote \\.\COM14
break main
continue
bt
continue
