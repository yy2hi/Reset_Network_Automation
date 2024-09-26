#!/bin/bash

# 실행할 서버 목록
# server=("192.168.10.92")
servers=("172.31.5.7" "172.31.5.8" "172.21.5.14" "172.21.5.15" "172.21.5.16" "172.21.5.17" "172.21.5.18" "172.21.5.19" "172.21.5.101")

# 서버 비밀번호
password="asdf"

# 각 서버에서 실행할 명령들
cleanup_script="
# 모든 ip netns 삭제
for netns in \$(ip netns list | awk '{print \$1}'); do
    ip netns del \"\$netns\"
    echo \"Deleted namespace: \$netns\"
done

# network-scripts 초기화
cd /etc/sysconfig/network-scripts/
rm -f ifcfg-net-*

# ifcfg-eno*.* 중 .숫자가 붙은 파일들만 삭제 (물리 인터페이스는 제외)
find . -name 'ifcfg-eno*.[0-9]*' -exec rm -f {} \;

# ifcfg-enp*.* 중 .숫자가 붙은 파일들만 삭제 (물리 인터페이스는 제외)
find . -name 'ifcfg-enp*.[0-9]*' -exec rm -f {} \;

# ifcfg-eno*.* 및 ifcfg-enp*.*  ip link 삭제
for ifcfg in \$(ip link show | grep -o 'ifcfg-eno[0-9]*\\.[0-9]*\\|ifcfg-enp[0-9]*\\.[0-9]*'); do
    echo \"Disabling and deleting interface: \$ifcfg\"
    ip link set \"\$ifcfg\" down
    ip link delete \"\$ifcfg\"
done

# vnet[숫자]로 시작하는 인터페이스 모두 삭제
for vnet in \$(ip link show | grep -o 'vnet[0-9]*'); do
    echo \"Disabling and deleting vnet interface: \$vnet\"
    ip link set \"\$vnet\" down
    ip link delete \"\$vnet\"
done

# net-[숫자]로 시작하는 인터페이스 모두 삭제
for net in \$(ip link show | grep -o 'net-[0-9]*'); do
    echo \"Disabling and deleting net interface: \$net\"
    ip link set \"\$net\" down
    ip link delete \"\$net\"
done

echo \"Deleted all sub-interface, vnet, and net interfaces!!\"

# /tmp 디렉토리에서 iptables-bak-vr-xx, sg.rules, subnet.rules 파일 삭제
cd /tmp
rm -f iptables-bak-vr-* sg.rules subnet.rules
echo \"Deleted all iptables backup, sg rules, subnet rules files!!\"

# ebtables 초기화
ebtables -F
ebtables -X
ebtables -P INPUT ACCEPT
ebtables -P FORWARD ACCEPT
ebtables -P OUTPUT ACCEPT
echo \"ebtables reset completed!!\"

# iptables 초기화
iptables -F
iptables -X
iptables -Z
iptables -t nat -F
iptables -t nat -X
iptables -t nat -Z
iptables -t mangle -F
iptables -t mangle -X
iptables -t mangle -Z
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
echo \"iptables reset completed!!\"

# NetworkManager 재시작
systemctl restart NetworkManager
echo \"NetworkManager restarted!!\"
"

# 모든 서버에 대해 스크립트 실행
for server in "${servers[@]}"; do
    echo "Executing cleanup script on server: $server"
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@"$server" "bash -s" <<EOF
$cleanup_script
EOF
    echo "Cleanup script completed on server: $server"
    echo "-------------------------------------------------"
done

echo "All servers have completed the cleanup process!!"


