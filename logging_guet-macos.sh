#!/bin/bash

# ==========================================
# 脚本说明：这是一个用于桂林电子科技大学（GUET）校园网自动登录的Shell脚本。
# 适用于macOS系统，通过模拟浏览器请求实现自动登录。
# 脚本会检查当前网络连接状态，如果未连接则自动进行登录操作。
# ==========================================

# ==========================================
# 用户配置部分：请根据实际情况修改以下变量
# ==========================================
YourID="250032305018"           # 学号：替换为你的实际学号，用于登录认证
Password="137683zhujian@"       # 密码：替换为你的实际密码，用于登录认证
YourISP="glgd"                  # ISP（互联网服务提供商）：校园网的运营商标识，这里是广电网络
JumpIP="1.2.3.4"                # 跳转IP：一个非认证IP地址，用于触发校园网网关的重定向机制

# 校园网请留空
# 中国移动 cmcc
# 中国联通 unicom
# 中国电信 telecom


# ==========================================

# 将密码转换为Base64编码，并去除填充字符'='
# 原因：校园网登录接口要求密码以Base64格式传输，去除填充字符是为了符合接口规范
base64_Password=$(echo -n "$Password" | base64 | tr -d '=')

echo "Checking Internet connection..."

# 使用HTTP状态码检测网络连接状态：尝试请求百度首页
# 原因：如果未登录校园网，网关会重定向请求；只有真正联网时才会返回200状态码
# 使用--max-time 3限制超时时间，避免长时间等待
check_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://www.baidu.com)

echo "HTTP Status Code: $check_status"

# 如果状态码不是200，说明网络未连接，需要执行登录逻辑
if [ "$check_status" != "200" ]; then
    echo "Internet access blocked. Try Auto Connecting..."

    # 使用curl发起HTTP请求到JumpIP，并跟踪重定向获取最终URL
    # 原因：校园网网关会将未认证请求重定向到登录页面，通过-L跟踪重定向并获取最终URL
    # 使用%{url_effective}获取重定向后的最终URL，其中包含必要的登录参数
    # 添加User-Agent和Accept头模拟浏览器请求，避免被识别为脚本
    url_redirect=$(curl -s -L -w '%{url_effective}' "http://$JumpIP/" \
        -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
        -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36' -o /dev/null)

    # 检查是否成功获取到重定向URL
    # 原因：如果URL为空或不包含查询参数，说明网络连接或网关有问题
    if [ -z "$url_redirect" ] || [[ "$url_redirect" != *"?"* ]]; then
        echo "Failed to retrieve redirect URL from JumpIP. Please check Wi-Fi connection."
        exit 1
    fi

    # 提取URL中的查询参数部分（问号后的部分）
    # 原因：重定向URL包含登录所需的参数，如用户IP、MAC地址等
    query_string=$(echo "$url_redirect" | awk -F'?' '{print $2}')
    echo "Query String: $query_string"

    # 解析查询参数，将其转换为易读的格式
    # 原因：便于后续提取特定参数
    params=""
    IFS='&' read -r -a pairs <<< "$query_string"
    for pair in "${pairs[@]}"; do
        key=$(echo "$pair" | cut -d '=' -f1)
        value=$(echo "$pair" | cut -d '=' -f2-)
        params="$params$key=$value, "
    done
    params=$(echo "$params" | sed 's/, $//')

    # 从解析的参数中提取关键信息
    # wlanuserip: 用户IP地址
    # wlanacname: AC（接入控制器）名称
    # wlanacip: AC IP地址
    # wlanusermac: 用户MAC地址
    # 原因：这些参数是校园网登录接口必需的，用于标识用户和设备
    wlan_user_ip=$(echo "$params" | awk -F'wlanuserip=' '{print $2}' | cut -d ',' -f1)
    wlan_ac_name=$(echo "$params" | awk -F'wlanacname=' '{print $2}' | cut -d ',' -f1)
    wlan_ac_ip=$(echo "$params" | awk -F'wlanacip=' '{print $2}' | cut -d ',' -f1)
    wlan_user_mac_raw=$(echo "$params" | awk -F'wlanusermac=' '{print $2}' | cut -d ',' -f1)

    # 去除MAC地址中的连字符或冒号，转换为纯数字格式
    # 原因：校园网接口要求MAC地址格式为连续的十六进制数字
    wlan_user_mac=$(echo "$wlan_user_mac_raw" | tr -d ':-')

    echo "Extracted Params -> IP: $wlan_user_ip, MAC: $wlan_user_mac"

    # 检查是否成功提取到必要参数
    # 原因：如果IP或MAC地址为空，登录将失败
    if [ -z "$wlan_user_ip" ] || [ -z "$wlan_user_mac" ]; then
        echo "Failed to extract required parameters from Portal URL."
        exit 1
    fi

    # 构造登录请求的URL
    # 原因：根据校园网Drcom系统的API规范构建完整的登录URL
    # callback=dr1004: 指定回调函数格式
    # login_method=1: 使用标准登录方法
    # user_account: 格式为 ,0,学号@ISP
    # user_password: Base64编码的密码，后加=
    # 其他参数：从重定向URL中提取的网络参数
    login_url="http://10.0.1.5:801/eportal/portal/login?callback=dr1004&login_method=1&user_account=%2C0%2C${YourID}%40${YourISP}&user_password=${base64_Password}%3D&wlan_user_ip=${wlan_user_ip}&wlan_user_ipv6=&wlan_user_mac=${wlan_user_mac}&wlan_ac_ip=${wlan_ac_ip}&wlan_ac_name=${wlan_ac_name}&jsVersion=4.2&terminal_type=1&lang=zh-cn&v=3713&lang=zh"

    echo "Sending login request..."

    # 向Drcom服务器发送登录请求
    # 原因：模拟浏览器发送POST请求到登录接口
    # 使用-A指定User-Agent模拟真实浏览器
    # 使用-H指定Referer头，避免被识别为异常请求
    # -o /dev/null丢弃响应内容，只获取状态码
    curl_response=$(curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
        -H "Referer: http://10.0.1.5/" \
        "$login_url" -o /dev/null -w "%{http_code}")

    # 检查登录请求的响应状态码
    # 原因：200表示请求成功，其他状态码表示失败
    if [ "$curl_response" -eq 200 ]; then
        echo "Login request successful."
        # 等待1秒让网络连接生效，然后ping测试连接
        # 原因：登录后需要短暂时间让认证生效，使用阿里DNS服务器测试连接
        sleep 1
        ping -c 2 223.5.5.5
    else
        echo "Login request failed with status code: $curl_response"
    fi

else
    echo "You are already connected to the Internet!"
fi