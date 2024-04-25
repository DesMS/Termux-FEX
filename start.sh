# -------------------------
# Start configuration
# -------------------------
export directories="
${TMPDIR}:/tmp
${HOME}/debian-amd64/root:/root
${HOME}/debian-amd64/home:/home
/proc:/proc
/dev:/dev
/sys:/sys
${HOME}/vulkan:/vulkan
${HOME}/fake/cpuinfo:/proc/cpuinfo
${HOME}/fake/stat:/proc/stat
${HOME}/fake/vmstat:/proc/vmstat
${HOME}/fake/uptime:/proc/uptime
${HOME}/fake/loadavg:/proc/loadavg
${HOME}/fake/version:/proc/version
${HOME}/fake/sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap
${HOME}/fake/shm:/dev/shm
/proc/self/fd:/dev/fd
/dev/urandom:/dev/random
/proc/self/fd/0:/dev/stdin
/proc/self/fd/1:/dev/stdout
${HOME}/proc/self/fd/2:/dev/stderr
/linkerconfig
${HOME}/BeamNG.drive:/BeamNG.drive
"
export share="
/home/main
/root
"
# -------------------------
# End configuration
# -------------------------

start_x() {
  if [[ -z "$(ps aux | grep "app_process" | grep "com.termux.x11")" ]]; then
    echo "Starting x11 and OpenGL server"
    # Kill off all others servers
    pkill -9 virgl_test_server &>/dev/null
    pkill -9 pulseaudio &>/dev/null
    rm -rf ${TMPDIR}/* &>/dev/null
    XDG_RUNTIME_DIR=${TMPDIR} virgl_test_server_android & # Adreno 750 GL support
    export GALLIUM_DRIVER=virpipe
    XDG_RUNTIME_DIR=${TMPDIR} termux-x11 :0 -ac & # Termux x11 for our x server
    export DISPLAY=:0
    sleep 1 # Let the server start up
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
    pacmd load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 # Start pulseaudio
    openbox &>/dev/null & # Start our window manager (woo)
    echo "Started x11 and OpenGL server"
  else
    echo "x11 and OpenGL server already started"
  fi
}

print_usage() {
  echo -e "Usage: ./start.sh feature [user]\n"
  echo -e "\nAvailable Features:"
  echo "[qemu] - "
  echo "[x11, gl, opengl] - Only start the x11 server and OpenGL server"
  echo "[fex] - "
  echo "[none] - "
  echo -e "\nAvailable Users:"
  echo "[root] - The root user (Not recommended with FEX)"
  echo "[main] - A user with sudo privileges (Sudo does not work with FEX)"
  echo "If no user is chosen, it will default to \"root\""
  echo -e "\nTermux FEX v1.0.0"
}

if [[ -z "$2" ]]; then
  echo "Chose user \"root\""
  export USER_PROOT="root"
  export HOME_PROOT="/root"
else
  export USER_PROOT="${2,,}"
  if [[ "$USER_PROOT" == "root" || "$USER_PROOT" == "main" ]]; then
    echo "Chose user \"root\""
    export HOME_PROOT="/root"
  elif [[ "$USER_PROOT" == "main" ]]; then
    echo "Chose user \"main\""
    export HOME_PROOT="/home/main"
  else
    print_usage
    exit 0
  fi
fi

export ARGS=""

while IFS= read -r line; do
    echo "... $line ..."
done <<< "$directories"

if [[ "$1" == "qemu" ]]; then
  start_x

  proot $ARGS
elif [[ "$1" == "x11" || "$1" == "gl" || "$1" == "opengl" ]]; then
  start_x
elif [[ "$1" == "fex" ]]; then
  start_x
elif [[ "$1" == "none" ]]; then
  start_x
else
  print_usage
fi

exit 0
