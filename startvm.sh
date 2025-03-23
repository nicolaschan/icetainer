#!/bin/sh
MEMORY_MIB=2048

mkdir -p /tmp
qemu-system-x86_64 -enable-kvm -m $MEMORY_MIB -cpu host -nographic \
  -drive if=virtio,file=/app.qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::25560-:25565 -device virtio-net-pci,netdev=net0 \
  -device virtio-serial \
  -chardev socket,path=/tmp/qga.sock,wait=off,server=on,id=qga0 \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -qmp unix:/tmp/qemu-sock,server,nowait \
  -monitor unix:/tmp/qemu_monitor.sock,server,nowait
