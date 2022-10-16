#!/bin/bash

get_data() {
    cat <<EOF
    {
        "jsonrpc":"2.0",
        "method": "$1",
        "params": $2,
        "id":1
    }
EOF
}

call_rpc() {
    echo $0 $1 $2 $3 $4
    ctype="Content-Type: application/json" 
    curl -H "$ctype" --data "$(get_data $1 $2)" $3:$4 | python3 -m json.tool 
}

# split on \n and print 1st slice
#| awk -F"\n" '{ print $1 }' \


read -p "Enter method name: " meth
read -p "Enter params(if any): " params
read -p "Enter ip addr(def localhost): " url
read -p "Enter port(def 9933): " port

if [[ $meth = "" ]]; then
    echo "enter method name"
    exit
fi

if [[ $params = "" ]]; then 
    params="[]"
fi

if [[ $url = "" ]]; then 
    url="localhost"
fi

if [[ $port = "" ]]; then 
    port="9933"
fi

call_rpc "$meth" "$params" "$url" "$port"

