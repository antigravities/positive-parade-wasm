#!/bin/bash

set -eo pipefail

if [ "$CLEAN" != "" ]; then
    rm -f ubuntu.img
    rm -f positiveparade.tgz
    rm -f positiveparade.wasm
    rm -f container2wasm.tar.gz
    rm -f c2w
fi

if [ ! -f "positiveparade.tgz" ]; then
    sudo apt install -y qemu-system-riscv64 u-boot-qemu opensbi sshpass expect

    if [ ! -f "ubuntu.img" ]; then
        wget "https://cdimage.ubuntu.com/releases/noble/release/ubuntu-24.04-preinstalled-server-riscv64.img.xz" -O ubuntu.img.xz
        
        xz -vdk ubuntu.img.xz
        rm ubuntu.img.xz

        qemu-img resize -f raw ubuntu.img +5G

#         sudo losetup -Pf ubuntu.img

#         rm -rf /tmp/cloudinit
#         mkdir /tmp/cloudinit

#         BASE=$(sudo losetup --raw -j $(pwd)/ubuntu.img -O NAME | head -2 | tail -1)

#         sudo mount ${BASE}p12 /tmp/cloudinit

#         sudo tee /tmp/cloudinit/user-data > /dev/null << EOF
# chpasswd:
#     users:
#     - name: ubuntu
#       password: ubuntu
#       type: text
#     expire: False
# EOF

#         exit 1

#         sync
#         sudo umount /tmp/cloudinit
#         rm -r /tmp/cloudinit
#         sudo losetup -d $BASE
    fi

    if [ -f "qemu.pid" ]; then
        kill -SIGHUP $(cat qemu.pid)
        rm qemu.pid
        sleep 5
    fi

    qemu-system-riscv64 \
        -machine virt -m 2048 -smp 4 \
        -bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin \
        -kernel /usr/lib/u-boot/qemu-riscv64_smode/uboot.elf \
        -device virtio-net-device,netdev=eth0 -netdev user,id=eth0,hostfwd=tcp::63772-:22 \
        -device virtio-rng-pci \
        -drive file="ubuntu.img",format=raw,if=virtio \
        -daemonize -pidfile qemu.pid -display none

    i=0

    cat <<EOF > /tmp/Dockerfile
FROM riscv64/alpine:edge

RUN apk --no-cache add git nano bash curl

ENV PS1="\[\e[31m\][\[\e[m\]\[\e[38;5;172m\]\u\[\e[m\] \[\e[38;5;214m\]\W\[\e[m\]\[\e[31m\]]\[\e[m\]\\\$ "

ENTRYPOINT [ "/bin/bash" ]
EOF

    cat <<EOF > /tmp/install.sh
set -eo pipefail
sudo apt update
sudo apt install -y docker.io docker-buildx
sudo docker build . -t positiveparade
sudo docker save positiveparade -o positiveparade.tgz
sudo chown ubuntu:ubuntu positiveparade.tgz
EOF

    cat <<EOF > /tmp/reset.expect
#!/usr/bin/expect

set timeout 20

set cmd [lrange \$argv 0 end]

eval spawn \$cmd
expect "Current password:"
send "ubuntu\r";
expect "New password:"
send "ubuntu1\r";
expect "Retype new password:"
send "ubuntu1\r";
interact
EOF
    chmod +x /tmp/reset.expect

    while [ $i -lt 30 ]; do
        set +e

        /tmp/reset.expect sshpass -pubuntu ssh -p 63772 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 ubuntu@localhost

        if [ $? -eq 0 ]; then
            break
        fi

        i=$((i+1))
        sleep 10
    done

    set -eo pipefail

    if [ $i -eq 30 ]; then
        echo "Failed to connect to the VM"
        exit 1
    fi

    sleep 10

    sshpass -pubuntu1 scp -P 63772 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/Dockerfile ubuntu@localhost:/home/ubuntu/Dockerfile
    sshpass -pubuntu1 scp -P 63772 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/install.sh ubuntu@localhost:/home/ubuntu/install.sh
    sshpass -pubuntu1 ssh -p 63772 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@localhost "bash install.sh"

    sshpass -pubuntu1 scp -P 63772 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@localhost:/home/ubuntu/positiveparade.tgz positiveparade.tgz

    kill -SIGHUP $(cat qemu.pid)
    rm qemu.pid
fi

sudo docker load -i positiveparade.tgz

if [ ! -f "c2w" ]; then
    wget https://github.com/ktock/container2wasm/releases/download/v0.6.4/container2wasm-v0.6.4-linux-amd64.tar.gz -O container2wasm.tar.gz
    tar -xvf container2wasm.tar.gz
fi

sudo ./c2w --target-arch riscv64 positiveparade positiveparade.wasm