#! /bin/bash

cmd=""
# 4 sec delay
DELAY=4
mode="r"
exex_name="dfs"
tmp_dir=""
spawn_cmds=()
phrase=()
ed_pubkey=()
sr_pubkey=()
ed_addr=()
sr_addr=()
peer_id=""
key_phrase=""
num_of_validators=""
ports=(30000)
rpc_input=""
rpc_output=""
ports_ws=(40000)
ports_rpc=(50000)
localhost="127.0.0.1"
# ip_addr_list=("127.0.0.1")
spec_file="./customSpec.json"
raw_spec_file="./customSpecRaw.json"

remove() {
    if [ -f $1 ]; then
        rm $1
    fi
}

start_clean() { 
    for (( i=0; i < $num_of_nodes; i=i+1 )); do
        rm -rf "$tmp_dir/node$i"
    done
}

init_steps() {
    read -p "Number of nodes (3): " num_of_nodes
    read -p "Number of validators (3): " num_of_validators
    read -p "temp dir path (~/tmp): " tmp_dir

    if [[ $num_of_validators == "" ]]; then
        num_of_validators=3
    elif [ $num_of_validators -eq 0 ]; then
        echo "invalid num of validators!"
        exit
    fi

    if [[ $num_of_nodes == "" ]]; then
        num_of_nodes=3
    elif [ $num_of_nodes -eq 0 ]; then
        echo "invalid num of nodes!"
        exit
    fi

    if [[ $tmp_dir = "" ]]; then
        tmp_dir="$HOME/tmp"
    fi

    if [[ $mode = "" ]]; then
        mode="d"
    fi

    # if [ ! -f $raw_spec_file ]; then
    #     echo -e "\npls generate customSepcRaw.json spec file first!!\n"
    #     exit
    # fi
    for (( i=0; i<$num_of_nodes-1; i=i+1)); do
        ports+=( $( bc -q <<< "${ports[$i]} + 1" ) )
        ports_ws+=( $( bc -q <<< "${ports_ws[$i]} + 1" ) )
        ports_rpc+=( $( bc -q <<< "${ports_rpc[$i]} + 1" ) )
    done
    echo -e "\n\nRPC Port List:\n"
    for p in ${ports_ws[@]}; do
        echo -e "$p"
    done
    echo -e "\n\n"
    start_clean
}

get_data() {
    # echo -e "\n\nParams: $2"
    rpc_input="{
        \"jsonrpc\":\"2.0\",
        \"method\": \"$1\",
        \"params\": $2,
        \"id\":1
    }"
}

call_rpc() {
    get_data $1 "$2"
    ctype="Content-Type: application/json"
    rpc_output=$(curl -H "$ctype" --data "$rpc_input" $3:$4)
}

get_local_peer_id() {
    call_rpc "system_localPeerId" "[]" "$1" $2
    peer_id="$(echo $rpc_output | sed 's/.*\"\(12.*\)\",.*/\1/')"
}

generate_keys() {
    # block productions and finalisation
    # insert session keys
    # gran, babe, imol, audi

    # generate Ed25519 key for granpa
    file="tmp_key.txt"
    # collect ed addresses and phrases
    for (( i=0; i<$num_of_validators; i=i+1 )); do
        eval "./target/$mode/$exec_name key generate --scheme Ed25519 > $file"
        phrase+=("$(cat $file | head -1 | cut -d ":" -f 2- | xargs)")
        ed_addr+=("$(cat $file | tail -1 | cut -d ":" -f 2- | xargs)")
        ed_pubkey+=("$(cat $file | head -3 | tail -1 | cut -d ":" -f 2- | xargs)")
    done
    echo -e "\nphrases:\n" ${phrase[@]}
    echo -e "\nEds:\n" ${ed_addr[@]}

    # generate sr keys from pharse generated with above scheme
    # to be used for babe, imol and audi
    for (( i=0; i<$num_of_validators; i=i+1 )); do
        eval "./target/$mode/$exec_name key inspect --scheme Sr25519 '${phrase[i]}' > $file"
        sr_addr+=("$(cat $file | tail -1 | cut -d ":" -f 2- | xargs)")
        sr_pubkey+=("$(cat $file | head -3 | tail -1 | cut -d ":" -f 2- | xargs)")
    done
    echo -e "\nSrs:\n" ${sr_addr[@]}
    
    echo -e "\nKindly save the following session keys into customSpec.json file.\n"
    for (( i=0; i<$num_of_validators; i=i+1 )); do
        echo -e "\n"
        t="{
    \"grandpa\": \"${ed_addr[$i]}\",
    \"babe\": \"${sr_addr[$i]}\",
    \"im_online\": \"${sr_addr[$i]}\",
    \"authority_discovery\": \"${sr_addr[$i]}\"
}" 
        echo "$t"
        # echo "$t" | python3 -m json.tool
    done
    read -p "Once done, press return key to continue: " tmp
    echo -e "\nGenerating raw spec file.."
    gen_raw
}

prep_cmd() {
    local i=$1
    local port=$2
    local port_ws=$3
    local port_rpc=$4
    local ip_addr_peer=$5
    local port_peer=$6
    local id_peer=$7

    if [ mode != "d" ]; then
        mode="release"
    else
        mode="debug"
    fi
    local exec_path="./target/$mode/$exec_name"
    if [ ! -f $exec_path -o ! -x $exec_path ]; then
        echo -e "\n" $exec_path " file either doesn't exist or not an executable\n"
        exit
    fi

    if [[ $id_peer = "" || $port_peer = "" ]]; then
        other_node=""
    else
        other_node="--bootnodes /ip4/$ip_addr_peer/tcp/$port_peer/p2p/$id_peer"
    fi
    
    cmd="$exec_path \
    --base-path $tmp_dir/node$i \
    --chain $raw_spec_file \
    --port $port \
    --ws-port $port_ws \
    --rpc-port $port_rpc \
    --rpc-cors all \
    --no-telemetry \
    --validator \
    --rpc-methods Unsafe \
    --name node$i $other_node &"
}

spawn_nodes() {
    prep_cmd 0 ${ports[0]} ${ports_ws[0]} ${ports_rpc[0]} $localhost
    spawn_cmds+=("\"$cmd\"")
    # here log node params
    bash -c "eval $cmd"
    echo -e "\npls wait for $DELAY sec..\n"
    sleep $DELAY
    get_local_peer_id $localhost ${ports_rpc[0]}
    echo -e "\nParsed PeerId: " $peer_id

    for (( i=1; i < $num_of_nodes; i = i+1 )); do
        prep_cmd $i ${ports[$i]} ${ports_ws[$i]} ${ports_rpc[$i]} $localhost ${ports[$( bc -q <<< "$i-1" )]} $peer_id
        spawn_cmds+=("\"$cmd\"")
        # echo -e "\nrun cmd\n" $cmd
        # here log node params
        bash -c "eval $cmd"
        echo -e "\npls wait for $DELAY sec..\n"
        sleep $DELAY
        # get peer id of node, just started, for next iteration
        get_local_peer_id $localhost ${ports_rpc[$i]}
        echo -e "\nParsed PeerId " $peer_id
    done
}

restart_nodes() {
    clear
    echo -e "\restarting nodes.."
    for (( i=0; i < $num_of_nodes; i=i+1 )); do
        bash -c "eval ${spawn_cmds[$i]}"
        sleep $DELAY
    done
    echo -e "\n\n3nj0y!!!"
}

gen_spec() {
    echo -e "\nGenerating spec file\n"
    cmd="./target/$mode/$exec_name build-spec --disable-default-bootnode --chain staging > $spec_file"
    remove $spec_file
    eval $cmd
    if [ -f $spec_file ]; then
        echo "spec generated, pls check!"
    else
        echo "failed to generate the file!"
    fi   
}

proc_spec() {
    echo -e "\nProcessing the spec file\n"
    # 1.  balances [[]]
    #   [accid, balance with 18 dec]
    # 2. validatorCount -> ip
    # 3. minimumValidatorCount -> ip
    # 4. invulnerables []
    #   accids of those which we want to add as validator who wont be slashed
    # 5. stakers [[]] length = validatorCount
    #   [ controller, stash, stake_amount with 18 dec, "validator"/"nominator"]
    # 6. minNominatorBond -> ip
    # 7. minValidatorBond -> ip
    # 8. session {keys: [[]]} keys.length = validatorCount
    #   keys: [[ validator, validator, { grandpa: ed_key, babe: sr_key, im_online: sr_key, authority: sr_key}]]
    # 9. technicalComitte {members: []} members.length -> ip (anybody from balances array)
    # 10. elections: {members: []} memebers.length = same as above
    #   [member_addr, vote_weight]
    # 11. sudo {key: anyone from balances}
    # 12. society: {pot, member:[]} members.length = same




}

gen_raw() {
    if [ ! -f $spec_file ]; then
        echo "spec file not found!!."
        exit
    fi
    echo -e "\nGenerating raw spec file\n"
    remove $raw_spec_file
    cmd="./target/$mode/$exec_name \
    build-spec \
    --chain=$spec_file \
    --raw \
    --disable-default-bootnode > $raw_spec_file"
    eval $cmd
    if [ -f $raw_spec_file ]; then
        echo "raw spec generated."
    else
        echo "failed to generate the file!"
    fi
}

# insert_author_keys() {
#     echo "inserting author keys"
#     # inserting keys into nodes
#     # insering keys for 4 things; gran, babe, imol and audi
#     for (( j=0; j < $num_of_validators; j=j+1 )); do
#         # gran
#         call_rpc "author_insertKey" "[\"gran\",\"${phrase[$j]}\",\"${ed_pubkey[$j]}\"]" $localhost ${ports_rpc[$j]}
#         # echo $rpc_input
#         # echo $rpc_output
#         # other 3
#         others=("babe" "imol" "audi")
#         for i in {0..2}; do
#             call_rpc "author_insertKey" "[\"${others[$i]}\",\"${phrase[$j]}\",\"${sr_pubkey[$j]}\"]" $localhost ${ports_rpc[$j]}
#             # echo $rpc_input
#             # echo $rpc_output
#         done
#     done
#     echo "author key insertions done!!"
#     # restart the nodes after key insertions
#     # kill all nodes and restart
#     # wait some time before killings
#     sleep $DELAY
#     sleep $DELAY
#     pkill -9 $exec_name
#     sleep $DELAY
#     restart_nodes
# }

insert_author_keys() {
    echo "inserting author keys"
    # inserting keys into nodes

    for (( j=0; j < $num_of_validators; j=j+1 )); do
        # echo -e "\nInserting phrase: ${phrase[$j]}\n"
        # gran
        cmd="./target/$mode/$exec_name key insert \
        --base-path $tmp_dir/node$j \
        --chain customSpecRaw.json \
        --scheme Ed25519 \
        --suri '${phrase[$j]}' \
        --key-type gran"
        eval "$cmd"
        # other 3
        others=("babe" "imol" "audi")
        for (( i=0; i<3; i=i+1 )); do
            cmd="./target/$mode/$exec_name key insert \
            --base-path $tmp_dir/node$j \
            --chain customSpecRaw.json \
            --scheme Sr25519 \
            --suri '${phrase[$j]}' \
            --key-type ${others[$i]}"
            eval "$cmd"
        done
    done
    echo "author key insertions done!!"
    # restart the nodes after key insertions
    # kill all nodes and restart
    # wait some time before killings
    sleep $DELAY
    sleep $DELAY
    pkill -9 $exec_name
    sleep $DELAY
    restart_nodes
}

post_spawn() {
    echo "post spawn"
    insert_author_keys
}

menu() {
    while true; do
        clear
        echo -e "\n0 - generate spec\n1 - process spec\n2 - generate raw\n3 - spawn nodes\n4 - exit\n"
        read -p "Choice: " choice

        if [ -z $choice ]; then
            continue
        fi

        if [ $choice -eq 0 ]; then
            gen_spec; break
        elif [ $choice -eq 1 ]; then
            proc_spec; break
        elif [ $choice -eq 2 ]; then
            gen_raw; break
        elif [ $choice -eq 3 ]; then
            init_steps; generate_keys; spawn_nodes; post_spawn; break
        elif [ $choice -eq 4 ]; then
            echo -e "\nthank u for using this script!!\n";break
        else
            read -p "Invalid choice (press return key to continue): " _
        fi
    done
}

start() {
    read -p "Enter mode (r): " mode
    read -p "Enter binary name (dfs): " exec_name

    if [ $mode == "d" ]; then
        mode="debug"
    else
        mode="release"
    fi
    
    if [ -z $exec_name ]; then
        exec_name="dfs"
    fi

    menu
}

start