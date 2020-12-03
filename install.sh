function easy_kube_install_main() {
  cd $HOME
  for fn in .zshrc .bashrc; do
    if [ -f $fn ];then
      if [ $(grep -c "easy_kubectl" $fn) -eq '0' ]; then
        echo 'source $HOME/.easy_kubectl/init.sh' >> $fn
      fi
    fi
  done
  mkdir -p .easy_kubectl
  cd $HOME/.easy_kubectl
cat <<\EOF > init.sh
#!/bin/bash
BASE_PATH=~/.easy_kubectl
VARIABLES_FN=$BASE_PATH/variables.sh
function isapply() {
  kubectl apply -f <(istioctl kube-inject -f $1)
}

function __k_add_history() {
  HISTORY=$HOME/.easy_kubectl/.history
  sed -i '/^'$1'$/d' $HISTORY
  echo $1 >> $HISTORY
}

function k() {
  if [[ $1 = l ]]; then
    for i in `seq 0 100`; do
      ns=$(eval echo '$KUBE_NS'$i)
      if [[ $ns != "" ]]; then
        echo $i: $ns
      fi
    done
    if [[ $KUBE_CONTEXT = "" ]]; then
      echo current: $KUBE_NS
    else
      echo current: $KUBE_CONTEXT/$KUBE_NS
    fi
  elif [[ $1 =~ ^[0-9]+$ ]]; then
    varname='$KUBE_NS'$1
    if [[ -n $2 ]]; then
      eval "export "'KUBE_NS'"$1=$2"
    fi
    export KUBE_NS=`eval echo $varname`
    echo namespace is now set to:
    echo $1: $KUBE_NS
    easy_kubectl_export_variables $VARIABLES_FN
  elif [[ $1 = c ]]; then
    export KUBE_CONTEXT=$2
    echo context is now set to \'$KUBE_CONTEXT\'
  elif [[ $# -lt 2 ]]; then
    NS_LIST="$(cat $HOME/.easy_kubectl/.history|tac)"
    NS_RESULT="$(echo $NS_LIST|xargs echo)"
    for kns in $(kubectl get ns -ojsonpath='{.items[*].metadata.name}'); do
      if [[ $(echo "$NS_LIST"|sed -n '/^'$kns'$/p') = "" ]]; then
        NS_RESULT="$NS_RESULT $kns" 
      fi
    done
    QUERY=""
    if [[ -n $1 ]]; then
      QUERY="--query=$1 -1 -0"
    fi
    NEW_NS=$(echo "$NS_RESULT"|tr ' ' '\n'|$HOME/.easy_kubectl/fzf --prompt="search for namespace: " --tiebreak=end,index $QUERY)
    UNCHANGED="(unchanged)"
    if [[ $NEW_NS != "" ]]; then
      export KUBE_NS=$NEW_NS
      __k_add_history $NEW_NS
      UNCHANGED=""
    fi
    echo "Current Namespace$UNCHANGED:"
    echo $KUBE_NS
  else
    if [[ $KUBE_CONTEXT = "" ]]; then
      echo kubectl -n $KUBE_NS $@ >&2
      kubectl -n $KUBE_NS $@
    else
      echo kubectl -n $KUBE_NS --context=$KUBE_CONTEXT $@ >&2
      kubectl -n $KUBE_NS --context=$KUBE_CONTEXT $@
    fi
  fi
}

function p() {
  ip=$(kubectl -n $KUBE_NS --context=$KUBE_CONTEXT get svc powerful-cases -ojsonpath='{.spec.clusterIP}')
  
  if [[ $# = "0" ]]; then
    c=$(cat)
    curl $ip/y -d "$c"
  elif [[ $# = "1" && $1 != /* ]]; then
    curl $ip/y -d "$1"
  else
    path=$1
    shift 1

    array=()
    for((i=1;i<=$#;i++)); do
      array[${i}]="${!i}"
    done
    curl $ip$path "${array[@]}"
  fi

  echo
}

function update_k() {
  source <(curl -fsSL https://github.com/zhranklin/easy_kubectl/archive/master.tar.gz | tar xzO easy_kubectl-master/install.sh)
}

function easy_kubectl_export_variables() {
  fn=$1
  echo export KUBE_NS=$KUBE_NS > $fn
  for i in `seq 0 100`; do
    echo export KUBE_NS$i=`eval echo '$KUBE_NS'$i` >> $fn
  done  
}
source $VARIABLES_FN

COMPLETE_FN=$BASE_PATH/load_kube_complete.sh
source $COMPLETE_FN

EOF
cat <<\EOF > load_kube_complete.sh
#!/bin/bash
FILE=~/.easy_kubectl/compl
kubectl completion bash > $FILE

LINE=$(sed -n -e '/__kubectl_override_flag_list=/=' $FILE)
sed -i ${LINE}'s/ \(--namespace\|-n\)//g' $FILE

for i in $(sed -n -e '/complete.*__start_kubectl.*kubectl/=' $FILE); do
  sed -i $i's/\bkubectl\b/k/g' $FILE
done

#查找__kubectl_override_flags()的行号
LINE=$(sed -n -e '/__kubectl_override_flags()/=' $FILE)
#查找__kubectl_override_flags()函数结尾
LINE=$(sed -n -e '1,'$LINE'd;/^\s*\}\s*$/=' $FILE | head -1)
#加入代码
sed -i $LINE'iecho "-n=$KUBE_NS"' $FILE
sed -i $LINE'iecho "--context=$KUBE_CONTEXT"' $FILE

source $FILE

EOF
}
touch $HOME/.easy_kubectl/.history
if [ ! -f $HOME/.easy_kubectl/fzf ];then
  wget https://github.com/junegunn/fzf/releases/download/0.24.3/fzf-0.24.3-linux_amd64.tar.gz -O fzf.tar.gz
  tar xzf fzf.tar.gz
  mv fzf $HOME/.easy_kubectl/fzf
fi
(easy_kube_install_main) && source ~/.easy_kubectl/init.sh
k 0 default
echo successfully installed easy_kubectl!

