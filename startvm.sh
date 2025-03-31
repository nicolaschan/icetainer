#!/bin/bash
MEMORY_MIB=2048
SNAPSHOT_NAME="vm_snapshot_latest"
VM_IMAGE="/app.qcow2"

if qemu-img snapshot -l "$VM_IMAGE" | grep -q $SNAPSHOT_NAME; then
  LOADVM_ARG="-loadvm $SNAPSHOT_NAME"
else
  LOADVM_ARG=""
fi

echo "LOADVM_ARG=$LOADVM_ARG"

mkdir -p /tmp
qemu-system-x86_64 -enable-kvm -m $MEMORY_MIB -cpu host -nographic \
  -drive if=virtio,file="$VM_IMAGE" \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::25560-:25565 -device virtio-net-pci,netdev=net0 \
  -device virtio-serial \
  -chardev socket,path=/tmp/qga.sock,wait=off,server=on,id=qga0 \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -qmp unix:/tmp/qemu-sock,server,nowait \
  -monitor unix:/tmp/qemu_monitor.sock,server,nowait $LOADVM_ARG
