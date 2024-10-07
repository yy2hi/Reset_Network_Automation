#!/bin/bash

delete_all_netns() {
    netns_list=$(ip netns list)

    if [ -n "$netns_list" ]; then
        for netns in $netns_list; do
            ip netns delete "$netns"
            echo "Deleted network namespace: $netns"
        done
    else
        echo "No network namespaces found."
    fi
}

# 네트워크 네임스페이스 삭제
delete_all_netns

# net-으로 시작하는 모든 연결 목록을 가져옴
ext-veth_connections=$(ip link show | grep "^ext-br-veth")
# 해당 연결을 하나씩 삭제
for conn in $ext-veth_connections; do
    nmcli connection delete "$conn"
    ip link delete "$conn"
    echo "Deleted connection: $conn"
done

# net-으로 시작하는 모든 연결 목록을 가져옴
int-veth_connections=$(ip link show | grep "^int-br-veth")
# 해당 연결을 하나씩 삭제
for conn in $int-veth_connections; do
    nmcli connection delete "$conn"
    ip link delete "$conn"
    echo "Deleted connection: $conn"
done

# net-으로 시작하는 모든 연결 목록을 가져옴
vnet_connections=$(nmcli -t -f NAME connection show | grep "^vnet")
# 해당 연결을 하나씩 삭제
for conn in $vnet_connections; do
    nmcli connection delete "$conn"
    ip link delete "$conn"
    echo "Deleted connection: $conn"
done

net_connections=$(nmcli -t -f NAME connection show | grep "^net-")
# 해당 연결을 하나씩 삭제
for conn in $net_connections; do
    nmcli connection delete "$conn"
    ip link delete "$conn"
    echo "Deleted connection: $conn"
done

connections=$(nmcli -t -f NAME connection show | grep "\.[0-9]\+$")

# 해당 연결을 하나씩 삭제
for conn in $connections; do
    nmcli connection delete "$conn"
    ip link delete "$conn"
    echo "Deleted connection: $conn"
done

# 필터 테이블 초기화
ebtables -F

# NAT 테이블 초기화
#ebtables -t nat -F

# BROUTE 테이블 초기화
#ebtables -t broute -F

# 필터 테이블의 모든 체인의 기본 정책을 ACCEPT로 설정
ebtables -P INPUT ACCEPT
ebtables -P OUTPUT ACCEPT
ebtables -P FORWARD ACCEPT

# NAT 테이블의 모든 체인의 기본 정책을 ACCEPT로 설정
#ebtables -t nat -P PREROUTING ACCEPT
#ebtables -t nat -P OUTPUT ACCEPT
#ebtables -t nat -P POSTROUTING ACCEPT

# BROUTE 테이블의 모든 체인의 기본 정책을 ACCEPT로 설정
#ebtables -t broute -P BROUTING ACCEPT

# 모든 체인의 규칙 삭제
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# 모든 사용자 정의 체인 삭제
iptables -X
iptables -t nat -X
iptables -t mangle -X
iptables -t raw -X

# 기본 체인의 정책을 ACCEPT로 설정
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -P PREROUTING ACCEPT
iptables -t nat -P POSTROUTING ACCEPT
iptables -t nat -P OUTPUT ACCEPT
iptables -t mangle -P PREROUTING ACCEPT
iptables -t mangle -P OUTPUT ACCEPT
iptables -t mangle -P FORWARD ACCEPT
iptables -t mangle -P POSTROUTING ACCEPT
iptables -t mangle -P INPUT ACCEPT
iptables -t raw -P PREROUTING ACCEPT
iptables -t raw -P OUTPUT ACCEPT


echo "All net- connections deleted."


remove_bridge_line() {
    local interface_name="$1"
    config_file="/etc/sysconfig/network-scripts/ifcfg-$interface_name"

    if [ -f "$config_file" ]; then
        # BRIDGE가 포함된 줄을 삭제
        sed -i '/^BRIDGE/d' "$config_file"
        echo "Removed BRIDGE line from $config_file"
    else
        echo "Error: $config_file does not exist."
    fi
}

for bridge_interface in $(ip link show | awk -F: '/-br/ {print $2}' | tr -d ' '); do
    interface="${bridge_interface%-br}"

    echo $interface

    # 사용자가 "end"를 입력하면 반복 종료
    if [ "$interface" == "end" ]; then
        echo "Exiting the script."
        break
    fi

    # 입력된 인터페이스가 존재하는지 확인 (nmcli 사용)
    if ! nmcli device status | grep -q "^$interface"; then
        echo "Error: Interface $interface does not exist."
        continue
    fi

    # 입력된 인터페이스가 존재하는지 확인 (nmcli 사용)
    if ! nmcli device status | grep -q "^$bridge_interface"; then
        echo "Error: Interface $interface does not exist."
        continue
    fi

    # IP 주소와 서브넷 마스크 가져오기 (첫 번째 IP 주소만 사용)
    ip_address=$(ip -4 addr show "$bridge_interface" | awk '/inet / {print $2}' | head -n 1)

    echo "IP : $ip_address"
    # 게이트웨이 가져오기
    gateway=$(ip route show default 0.0.0.0/0 dev $bridge_interface | awk '{print $3}')

    # DNS 서버 가져오기 (resolv.conf에서 첫 번째 DNS 서버만 사용)
    dns=$(grep -m 1 'nameserver' /etc/resolv.conf | awk '{print $2}')

    remove_bridge_line "$interface"

    nmcli conn reload

    nmcli conn mod "$interface" ipv4.method auto
    # IP 주소 설정
    if [ -n "$ip_address" ]; then
        nmcli conn mod "$interface" ipv4.addresses "$ip_address"
        echo "Set IP address $ip_address on $interface."
    else
        echo "Skipping IP address configuration for $interface due to missing IP."
    fi

    # 게이트웨이 설정
    if [ -n "$gateway" ]; then
        nmcli conn mod "$interface" ipv4.gateway "$gateway"
        echo "Set gateway $gateway on $interface."
    else
        echo "Skipping gateway configuration for $interface due to missing gateway."
    fi

    # DNS 서버 설정
    if [ -n "$dns" ]; then
        nmcli conn mod "$interface" ipv4.dns "$dns"
        echo "Set DNS $dns on $interface."
    else
        echo "Skipping DNS configuration for $interface due to missing DNS."
    fi

    # 설정 적용
    nmcli conn mod "$interface" ipv4.method manual
    nmcli conn up "$interface"
    nmcli conn del "$bridge_interface"
    # "-br"이 붙은 인터페이스의 정보 출력
    echo "The bridge interface name is: $bridge_interface"

    # 필요시 bridge_interface 변수로 추가 작업 가능
    # 예: nmcli를 사용하여 bridge_interface에 대해 추가 설정 수행
    # nmcli conn add type bridge ifname $bridge_interface

    echo "Network configuration completed for $interface."
done