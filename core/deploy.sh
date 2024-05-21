#!/bin/bash

# 脚本中的任何命令返回非零退出状态时，整个脚本会立即退出
#set -e

script_path=$(dirname "$0")
# 参数检查和使用说明
usage() {
    echo "Usage: $0 [--branch] [--message] [--url] [--path] [--server-id]"
    echo "Options:"
    echo "    --branch  Specify the branch name to commit and push to."
    echo "    --message  Specify the commit message."
    echo "    --url  Specify the repository url."
    echo "    --path  Specify the root directory of the repository, default is '/'."
    echo "    --server-id  Specify the server id configured in maven for repository authorization."
    exit 1
}

function moveFiles() {
  local source_dir=$1
  local target_dir=$2
  # 过滤文件 使用正则匹配
  local filters=$3

  # 获取目录所有文件 排除当前目录和上级目录
  local files=$(ls -a "$source_dir" | grep -vE "^\.$|^\.\.$")
  for file in $files; do
    # 判断是否需要过滤
    if [[ $filters =~ $file ]]; then
      continue
    fi

    if [[ -d "$source_dir/$file" ]]; then
      cp -rf "$source_dir/$file" "$target_dir/"
    else
      cp -f "$source_dir/$file" "$target_dir"
    fi
  done
}

read_mvn_script=$(cat <<'END_OF_STRING'
BEGIN {
    server_started = 0;
    found=0;
    username="";
    password="";
    privateKey="";
    passphrase="";
}

/<server>/ {
  server_started = 1;
  next;
}

/<\/server>/ {
  server_started = 0;
  if(found){
    exit 0;
  }
  next;
}

server_started && /<id>[^<]+<\/id>/ {
    match($0, /<id>([^<]+)<\/id>/);
    server_id = substr($0, RSTART + 4, RLENGTH - 9);
    if (server_id == id) {
        found = 1;
    }
    next;
}

is_ssh && found && /<privateKey>/ {
    gsub(/ /, "");
    match($0, /<privateKey>([^<]+)<\/privateKey>/);
    privateKey = substr($0, RSTART + 12, RLENGTH - 25);
    next;
}
is_ssh && found && /<passphrase>/ {
    gsub(/ /, "");
    match($0, /<passphrase>([^<]+)<\/passphrase>/);
    passphrase = substr($0, RSTART + 12, RLENGTH - 25);
    next;
}

!is_ssh && found && /<username>/ {
    match($0, /<username>([^<]+)<\/username>/);
    username = substr($0, RSTART + 10, RLENGTH - 21);
    next;
}
!is_ssh && found && /<password>/ {
    match($0, /<password>([^<]+)<\/password>/);
    password = substr($0, RSTART + 10, RLENGTH - 21);
    next;
}

END {
    if(!found){
      print "Error: not found server id:" id
      exit 1;
    }
    if(is_ssh) {
        if(!privateKey){
          print "Error: The privateKey configuration is missing";
          exit 1;
        }
        if(!passphrase){
          print "Error: The passphrase configuration is missing";
          exit 1;
        }
        print privateKey " " passphrase
    } else {
        if(!username){
          print "Error: The user name configuration is missing";
          exit 1;
        }
        if(!password){
          print "Error: The password configuration is missing";
          exit 1;
        }
        print username " " password
    }
}
END_OF_STRING
)

function readMavenConfig() {
    # 协议类型 0: https/1: ssh
    local is_ssh=$1;
    local server_id=$2;
    # 获取Maven的安装路径
    local maven_location=$(which mvn | sed "s/\/bin\/mvn//")
    if [[ -z $maven_location ]]; then
      echo "Maven not found, please install maven first."
      exit 1
    fi

    local mvn_conf_loc="$maven_location/conf/settings.xml"
    local res=$(awk -v id="$server_id" -v is_ssh="$is_ssh" "$read_mvn_script" "$mvn_conf_loc")
    local error=$(echo "$res" | grep "Error")
    if [[ -nz "$error" ]]; then
      echo "$error" >&2
      exit 1;
    fi
    echo "$res"
}

function authenticationWithSsh() {
    read -r privateKey passphrase <<< "$1"
    # 检查ssh代理进程是否启动
    # 进程被终止 需要重新认证
    local pid=$(ps -ef | grep "ssh-agent -s" | grep -v grep | awk '{print $2}')
    if [[ -z $pid ]]; then
      # 启动ssh代理进程
      eval "$(ssh-agent -s)"
    fi
    # 查看私钥对应的公钥指纹
    local pub_fingerprint=$(ssh-keygen -lf "$privateKey" | awk '{print $2}')
    local added_fingerprints=""
    local target_fingerprint="";

    local res=$(ssh-add -l &>/dev/null)
    if [[ -z "$res" ]]; then
       echo "The agent has no identities."
    else
       added_fingerprints=$(echo "$res" | awk '{print $2}')
    fi
    for added_fingerprint in $added_fingerprints; do
      if [[ $pub_fingerprint == $added_fingerprint ]]; then
         target_fingerprint="$added_fingerprint";
         break ;
      fi
    done

    if [[ -z $target_fingerprint ]]; then
      # 未添加ssh认证
      "$script_path/ssh-auth-helper.exp" "$privateKey" "$passphrase"
      echo "Authentication add successful."
    else
      echo "Authentication has been added.";
    fi
}

function authenticationWithHttps() {
    read -r username password <<< "$1"
    local url=$2
    local system_path=$(cd ~; pwd)
    echo "system_path: $system_path"
    local git_credential_path="$system_path/.gitstore"
    local git_config_path="$system_path/.gitconfig"
    if [[ ! -f "$git_config_path" ]]; then
      touch "$git_config_path"
      echo "Create git store file successful."
    fi
    local file_credential_config="helper = store --file $git_credential_path"
    local file_credential_search=$(grep "$file_credential_config" "$git_config_path")
    # 获取git-credential-manager行号
    local git_credential_manager_ln=0
    git_credential_manager_ln=$(grep -n "git-credential-manager" "$git_config_path" | awk -F: '{print $1}')
    if [[ -z "$file_credential_search" ]]; then
        local content="        $file_credential_config"
        awk -v line="$git_credential_manager_ln" -v str="$content" '
            NR == line {
                print str
                print $0 # 打印当前行的内容，可选，根据需要调整
                next
            }
            { print $0 }
        ' "$git_config_path" > "$git_config_path.tmp" && mv "$git_config_path.tmp" "$git_config_path"
        echo "Add file credential manager successful."
    fi

    local store_protocol=$(echo "$url" | grep -oE '^[^:]+://' | awk -F: '{print $1}')
    local store_host=$(echo "$url" | grep -oE '://[^/]+' | awk -F// '{print $2}')
    local store_username=""
    local store_password=""
    local store_url=""
    # 创建临时文件
    touch "$git_credential_path.tmp"
    while IFS= read -r line
    do
      if [[ $line =~ ^([^:]+)://([^:]+):([^@]+)@([^@]+)$ ]]; then
          protocol="${BASH_REMATCH[1]}"
          store_username="${BASH_REMATCH[2]}"
          store_password="${BASH_REMATCH[3]}"
          host="${BASH_REMATCH[4]}"
          store_url="$protocol://$host"
          if [[ "$store_url" == "$url" ]]; then
             store_protocol="$protocol"
             store_host="$host"
             break;
          else
             echo "$line" >> "$git_credential_path.tmp"
          fi
      fi
    done < "$git_credential_path"

    if [[ -z "$store_url" || "$store_username" != "$username" || "$store_password" != "$password" ]]; then
      # url改变
      store_url="$store_protocol://$username:$password@$store_host"
      echo "url: $store_url"
      echo "$store_url" >> "$git_credential_path.tmp"
      mv "$git_credential_path.tmp" "$git_credential_path"
      echo "Add credential successful."
    else
      echo "Credential has added."
    fi
    # 删除临时文件
    rm -rf "$git_credential_path.tmp"
}

# 初始化变量
branch=""
message=""
url=""
path="/"
server_id=""
protocol=""
remote_name="maven_origin"
# 需要忽略的文件或目录
git_ignores=("build" "packages")

# 解析参数
while [[ $# -gt 0 ]]; do
    key="$1"
    shift
    case $key in
        --branch)
            branch="$1"
            shift
            ;;
        --message)
            message="$1"
            shift
            ;;
        --url)
            url="$1"
            shift
            ;;
        --path)
            path="$1"
            shift
            ;;
        --server-id)
            server_id="$1"
            shift
            ;;
        *)
            # 未知参数
            usage
            ;;
    esac
done

if [[ -z $server_id ]]; then
  echo "Error: Server ID is required."
  usage;
  exit 1;
fi

if [[ $url == https://* ]]; then
  echo "The protocol type is https"
  config=$(readMavenConfig 0 "$server_id")
  authenticationWithHttps "$config" "$url"
elif [[ $url == git@* ]]; then
  echo "The protocol type is ssh"
  config=$(readMavenConfig 1 "$server_id")
  authenticationWithSsh "$config"
else
  echo "Wrong url format, please start with 'https://' or 'git@'."
  exit 1
fi

# 检查分支名称和提交信息是否已设置
if [[ -z "$branch" ]]; then
    echo "Error: Branch name is required."
    usage
fi

if [[ -z "$message" ]]; then
    echo "Error: Commit message is required."
    usage
fi

if [[ -z "$url" ]]; then
    echo "Error: Url is required."
    usage
fi
echo "message: $message, branch: $branch, url: $url"

base_dir=$(pwd)
workspace="$base_dir/workspace"
# 创建工作空间 github默认仓库在根目录 便于清理
mkdir "workspace"
cd "$workspace"
repo_path=$workspace
if [[ "$path" != "/" ]]; then
  repo_path="$workspace$path"
  rm -rf "$repo_path"
  mkdir "$repo_path"
  echo "clean directory: $repo_path"
fi
echo "repository path: $repo_path"

# 初始化git 不输出hint提示信息
# 将标准错误（stderr）重定向到/dev/null
git init 2>/dev/null
git remote add "$remote_name" "$url"
# 拉取所有分支到本地
git fetch "$remote_name"
if [[ $? -ne 0 ]]; then
    exit 1
fi
echo "fetch remote branches complete.";
# 解决git本地主分支名为master问题
remote_branch=$(git branch -r | grep "$branch" | sed "s/^ *$remote_name\///")
if [[ -z "$remote_branch" ]]; then
    echo "Not found branch: $branch";
    exit 1
fi

# 第一次拉取分支
git pull --set-upstream --rebase=merges "$remote_name" "$branch"
# 本地主分支名 git默认为master 可通过git config --global init.defaultBranch修改
local_branch=$(git branch | grep "*" | sed "s/* //")
if [ "$local_branch" != "$remote_branch" ]; then
  git branch -m "$remote_branch"
  echo "rename $local_branch to $remote_branch"
fi

git_ignore_path="$workspace/.gitignore"
git_ignore_file=$(ls -a | grep .gitignore)
if [[ -z "$git_ignore_file" ]]; then
  touch "$git_ignore_path"
  echo "add $git_ignore_path file"
fi

# 遍历忽略列表
for entry in "${git_ignores[@]}"; do
    # 使用grep检查.gitignore文件中是否包含该条目
    if ! grep -qFx "$entry" "$git_ignore_path"; then
        # 如果不包含，则添加到.gitignore文件
        echo "$entry" >> "$git_ignore_path"
        echo "Added '$entry' to $git_ignore_path"
    fi
done

# 复制目录和文件到仓库目录
moveFiles "$base_dir" "$repo_path" "^\\$workspace$"
git add .
## 提交到本地仓库
if ! git commit -m "$message"; then
    echo "Error: Failed to commit files."
    exit 1
fi

echo "pushing to remote..."
# 推送到远程分支
git push -u "$remote_name" "$branch" || {
    echo "Error: Failed to push to remote branch '$branch'."
    exit 1
}

echo "Pushing the remote branch succeeded: $url/$branch$path."
rm -rf "$workspace"