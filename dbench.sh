#!/bin/bash

display_usage () {
  echo "Usage: dbench.sh [-hda [sitename] | --init [-e | -d] [sitename (if not specified, it will default to site1.local)]] [\"<command to be executed on bench inside container>\"]"
  echo ''
  echo 'where:'
  echo '    -h    show this help text'
  echo '    -d [sitename]    enables developer mode for specified site'   
  echo '    -a    adds site-names to /etc/hosts file in the container to facilitate multisite access'
  echo '    --init [-e | -d] [sitename] initializes frappe-bench'
  echo '           -e  initializes frappe-bench and installs erpnext'
  echo '           -d  initializes frappe-bench and enables developer mode'
}

frappe_installer () {
  echo "starting frappe_docker setup"
  docker exec -i -u root frappe bash -c "cd /home/frappe && chown -R frappe:frappe ./*" 
  docker exec -it frappe bash -c "cd .. && bench init frappe-bench --ignore-exist --skip-redis-config-generation && cd frappe-bench"
  docker exec -it frappe bash -c "mv Procfile_docker Procfile && mv sites/common_site_config_docker.json sites/common_site_config.json"
  echo "frappe-bench folder setup"
  docker exec -it -u root frappe bash -c "apt-get install vim -y && apt-get install sudo -y && usermod -aG sudo frappe && printf '# User rules for frappe\nfrappe ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/frappe"
  echo "adding $1"
  docker exec -it frappe bash -c "bench new-site $1"
  docker exec -i -u root frappe bash -c "echo 127.0.0.1   $1 >> /etc/hosts"
  sudo su -c 'echo 127.0.0.1   $1 >> /etc/hosts'
  echo "$1 added"
}

if [[ $# -eq 0 ]]; then
  docker exec -it frappe bash "bench $@"

elif [[ $1 == 'init' && $2 == '-e' ]]
then
  if ! $3 then
    set -- "${@:1:2}" "site1.local"
  fi 
  frappe_installer $3
  echo "installing erpnext"
  docker exec -it frappe bash -c "bench get-app erpnext"
  docker exec -it frappe bash -c "bench --site $3 install-app erpnext"
  echo "finished"

elif [[ $1 == 'init' && $2 == '-d' ]]
then
  if ! $3 then
    set -- "${@:1:2}" "site1.local"
  fi
  frappe_installer $3
  docker exec -it frappe bash -c "bench --site $3 set-config \"developer_mode\" 1 &&  bench clear-cache"

elif [ $1 == 'init' ]
then
  if ! $2 then
    set -- "${@:1}" "site1.local"
  fi
  frappe_installer $2

else
  while getopts ':had:' option; do
    case "$option" in
      h)
         display_usage
         exit
         ;;
      a)
         a=$(docker exec -i frappe bash -c "cd ~/frappe-bench && ls sites/*/site_config.json" | grep -o '/.\+/')
         a="${a//$'\n'/ }"
         a=$(echo $a | tr -d / )
         result="127.0.0.1 ${a}"
         echo $result
         docker exec -u root -i frappe bash -c "echo ${result} | tee --append /etc/hosts"
         docker exec -itu root frappe bash -c "printf '# User rules for frappe\nfrappe ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/frappe"
         ;;
      d)
        docker exec -it frappe bash -c "bench --site $OPTARG set-config \"developer_mode\" 1 &&  bench clear-cache"
      \?)
        echo "Invalid option: -$OPTARG" >&2
        display_usage
        exit 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument." >&2
        display_usage
        exit 1
        ;;
    esac
  done
fi
