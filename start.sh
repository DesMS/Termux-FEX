# -------------------------
# Start configuration
# -------------------------

# 
# It is not recommended to change this unless you know what you're doing
# If you want to add a directory, it is recommended to do this:
# 
# DIRECTORIES={SOURCE_DIR}:{OUTPUT_DIR}
# 
# For example, if you have beamng in your home folder and you want to add that:
# 
# DIRECTORIES=${HOME}/BeamNG.drive:/BeamNG.drive
# 
# If you want to share directories between your installations (Such as you have /example in AMD64, but you want it in your ARM64 install, you can)
# 
# SHARED_DIRECTORIES=/example
# 
# Please note that the shared directory *HAS* to be in your AMD64 install
# 

# Check if the user has set a custom CPU model, if not, set to Snapdragon 8 Gen 3
if [[ -z "$CPU_MODEL" ]]; then
  export CPU_MODEL="Qualcomm Snapdragon 8 Gen 3"
fi

# Check if the user has set a custom install directory, if not, set to ~/.fex
if [[ -z "$INSTALL_DIR" ]]; then
  export INSTALL_DIR="${HOME}/.fex"
fi

# These are the default directories, these are needed for a long list of support
export DIRECTORIES="
$DIRECTORIES
${TMPDIR}:/tmp
${INSTALL_DIR}/debian-amd64/root:/root
${INSTALL_DIR}/debian-amd64/home:/home
/proc:/proc
/dev:/dev
/sys:/sys
/linkerconfig:/linkerconfig
${INSTALL_DIR}/vulkan:/vulkan
${INSTALL_DIR}/fake/stat:/proc/stat
${INSTALL_DIR}/fake/vmstat:/proc/vmstat
${INSTALL_DIR}/fake/uptime:/proc/uptime
${INSTALL_DIR}/fake/loadavg:/proc/loadavg
${INSTALL_DIR}/fake/version:/proc/version
${INSTALL_DIR}/fake/sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap
${INSTALL_DIR}/fake/shm:/dev/shm
/proc/self/fd:/dev/fd
/dev/urandom:/dev/random
/proc/self/fd/0:/dev/stdin
/proc/self/fd/1:/dev/stdout
/proc/self/fd/2:/dev/stderr
"

# These are some directories shared between AMD64 and ARM64
export SHARED_DIRECTORIES="
$SHARED_DIRECTORIES
/home/main
/root
/etc/passwd
/etc/group
/etc/shadow
/etc/gshadow
"

# Our required packages
# Format:
# {PACKAGE}:{REQUIRED_PACKAGE}
# (If REQUIRED_PACKAGE = 0, then that means it's a package required by another (Ex repo packages)
export required_packages="
x11-repo:0
proot:
pulseaudio:
debootstrap:
unzip:
git:
qemu-user-x86-64:
virglrenderer-android:x11-repo
termux-x11-nightly:x11-repo
openbox:x11-repo
"
# -------------------------
# End configuration
# -------------------------

# Never ask for user input
export APT_ARGS="-o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confnew'"

# Our custom check package function, it allows us to check if a package is installed
check_package() {
  # Query it, and see if it is installed, if it is, then we say 1, if not, 0
  package_check=$(dpkg-query -W --showformat='${Status}\n' "$1" 2> /dev/null | grep "install ok installed")
  if [[ -z "$package_check" ]]; then
    echo "0"
  else
    echo "1"
  fi
}

# This starts our x server
start_x() {
  # Check if termux x11 is running (There seems to be no way to shut it off once it starts)
  if [[ -z "$(ps aux | grep "app_process" | grep "com.termux.x11")" ]]; then
    echo "Starting x11 and OpenGL server"
    # Kill off all others servers
    pkill -9 virgl_test_server_android &>/dev/null
    pkill -9 pulseaudio &>/dev/null
    rm -rf ${TMPDIR}/* &>/dev/null
    XDG_RUNTIME_DIR=${TMPDIR} virgl_test_server_android & # GL support
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

# This function just prints the usage
print_usage() {
  echo -e "Usage: ./start.sh feature [user]\n"
  echo -e "\nAvailable Features:"
  echo "[qemu] - Start a x86_64 environment using proot with qemu-x86_64 (Use this for modifying the x86_64 filesystem)"
  echo "[x11, gl, opengl] - Only start the x11 server and OpenGL server (Recommended if you're switching between methods alot)"
  echo "[fex] - Start a x86_64 environment using proot with FEX (Recommended for performance, use qemu for modifying the filesystem)"
  echo "[update] - Update FEX to it's latest version and pass new args to it (User arg is ignored)"
  echo "[none] - Start a arm64 environment for the FEX filesystem (Recommended for building)"
  echo -e "\nAvailable Users:"
  echo "[root] - The root user (Not recommended with FEX)"
  echo "[main] - A user with sudo privileges (Sudo does not work with FEX)"
  echo "If no user is chosen, it will default to \"root\""
  echo -e "\nTermux FEX v1.0.0"
}

# Store the pkg install commands (1 = required by another package, 2 = required)
export install_1="pkg install"
export install_2="pkg install"
export needed_packages=""
# Read all the lines for the required packages
while IFS= read -r line; do
  if [[ ! -z "$line" ]]; then
    # Unformat? them
    export arr=(${line//:/ })
    export package="${arr[0]}"
    export needed="${arr[1]}"
    # Check if it's installed
    if [[ "$(check_package "$package")" == "0" ]]; then
      # Check if it needs a package
      if [[ ! -z "$needed" ]]; then
        # Check if it's a required package
        if [[ "$needed" == "0" ]]; then
          export needed_packages="${needed_packages}\n${package}"
          export install_1="${install_1} ${package}"
        else
          export needed_packages="${needed_packages}\n${package} (Depends ${needed})"
          export install_2="${install_2} ${package}"
        fi
      else
        export needed_packages="${needed_packages}\n${package}"
        export install_2="${install_2} ${package}"
      fi
    fi
  fi
done <<< "$required_packages"

# Check if we need some packages
if [[ ! -z "$needed_packages" ]]; then
  echo -e "You need to install:${needed_packages}\nBefore running this program.\n(You can run:)"
  export to_echo=""
  # Check if the required packages is installed, so we don't need to print a useless line
  if [[ "$install_1" != "pkg install" ]]; then
    to_echo="${install_1}; "
  fi
  to_echo="${to_echo}${install_2}"
  # Print the needed packages, and exit
  echo "$to_echo"
  exit 1
fi

# Check and create the install dir
if [[ ! -d "${INSTALL_DIR}" ]]; then
  mkdir "${INSTALL_DIR}"
fi

# The FEX variable is just a shortened version for the path to the fex install
export FEX=".fex-emu/RootFS/Debian_Bookworm"
# Our base args (AMD64)
export ARGS="-b ${INSTALL_DIR}/debian-amd64:/home/main/$FEX/ -b ${INSTALL_DIR}/debian-amd64:/root/$FEX/ -b ${INSTALL_DIR}/FEX:/home/main/.fex-emu -b ${INSTALL_DIR}/FEX:/root/.fex-emu"

# Go through all the directories
while IFS= read -r line; do
  # If the line isn't empty
  if [[ ! -z "$line" ]]; then
    # Parse the line, and add the binds to the args
    export arr=(${line//:/ })
    export source="${arr[0]}"
    export proot_out="${arr[1]}"
    ARGS="$ARGS -b ${source}:${proot_out} -b ${source}:/root/${FEX}/${proot_out} -b ${source}:/home/main/${FEX}/${proot_out}"
  fi
done <<< "$DIRECTORIES"

# Go through our shared directories
while IFS= read -r line; do
  # If the line isn't empty
  if [[ ! -z "$line" ]]; then
    # Add the binds to the args
    export ARGS="$ARGS -b ${INSTALL_DIR}/debian-amd64${line}:${line}"
  fi
done <<< "$SHARED_DIRECTORIES"

# If we don't have the fake dir, create it
if [[ ! -d "${INSTALL_DIR}/fake" ]]; then
  mkdir "${INSTALL_DIR}/fake"
fi

# spoofed /proc/loadavg
if [[ ! -f "${INSTALL_DIR}/fake/loadavg" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/loadavg"
0.12 0.07 0.02 2/165 765
EOF
fi

# spoofed /proc/stat
if [[ ! -f "${INSTALL_DIR}/fake/stat" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/stat"
cpu  1957 0 2877 93280 262 342 254 87 0 0
cpu0 31 0 226 12027 82 10 4 9 0 0
cpu1 45 0 664 11144 21 263 233 12 0 0
cpu2 494 0 537 11283 27 10 3 8 0 0
cpu3 359 0 234 11723 24 26 5 7 0 0
cpu4 295 0 268 11772 10 12 2 12 0 0
cpu5 270 0 251 11833 15 3 1 10 0 0
cpu6 430 0 520 11386 30 8 1 12 0 0
cpu7 30 0 172 12108 50 8 1 13 0 0
intr 127541 38 290 0 0 0 0 4 0 1 0 0 25329 258 0 5777 277 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
ctxt 140223
btime 1680020856
processes 772
procs_running 2
procs_blocked 0
softirq 75663 0 5903 6 25375 10774 0 243 11685 0 21677
EOF
fi

# spoofed /proc/uptime
if [[ ! -f "${INSTALL_DIR}/fake/uptime" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/uptime"
124.08 932.80
EOF
fi

# spoofed /proc/version
if [[ ! -f "${INSTALL_DIR}/fake/version" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/version"
Linux version 6.2.1-generic (proot@termux) (gcc (GCC) 12.2.1 20230201, GNU ld (GNU Binutils) 2.40) #1 SMP PREEMPT_DYNAMIC Wed, 01 Mar 2023 00:00:00 +0000
EOF
fi

# spoofed /proc/vmstat
if [[ ! -f "${INSTALL_DIR}/fake/vmstat" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/vmstat"
nr_free_pages 1743136
nr_zone_inactive_anon 179281
nr_zone_active_anon 7183
nr_zone_inactive_file 22858
nr_zone_active_file 51328
nr_zone_unevictable 642
nr_zone_write_pending 0
nr_mlock 0
nr_bounce 0
nr_zspages 0
nr_free_cma 0
numa_hit 1259626
numa_miss 0
numa_foreign 0
numa_interleave 720
numa_local 1259626
numa_other 0
nr_inactive_anon 179281
nr_active_anon 7183
nr_inactive_file 22858
nr_active_file 51328
nr_unevictable 642
nr_slab_reclaimable 8091
nr_slab_unreclaimable 7804
nr_isolated_anon 0
nr_isolated_file 0
workingset_nodes 0
workingset_refault_anon 0
workingset_refault_file 0
workingset_activate_anon 0
workingset_activate_file 0
workingset_restore_anon 0
workingset_restore_file 0
workingset_nodereclaim 0
nr_anon_pages 7723
nr_mapped 8905
nr_file_pages 253569
nr_dirty 0
nr_writeback 0
nr_writeback_temp 0
nr_shmem 178741
nr_shmem_hugepages 0
nr_shmem_pmdmapped 0
nr_file_hugepages 0
nr_file_pmdmapped 0
nr_anon_transparent_hugepages 1
nr_vmscan_write 0
nr_vmscan_immediate_reclaim 0
nr_dirtied 0
nr_written 0
nr_throttled_written 0
nr_kernel_misc_reclaimable 0
nr_foll_pin_acquired 0
nr_foll_pin_released 0
nr_kernel_stack 2780
nr_page_table_pages 344
nr_sec_page_table_pages 0
nr_swapcached 0
pgpromote_success 0
pgpromote_candidate 0
nr_dirty_threshold 356564
nr_dirty_background_threshold 178064
pgpgin 890508
pgpgout 0
pswpin 0
pswpout 0
pgalloc_dma 272
pgalloc_dma32 261
pgalloc_normal 1328079
pgalloc_movable 0
pgalloc_device 0
allocstall_dma 0
allocstall_dma32 0
allocstall_normal 0
allocstall_movable 0
allocstall_device 0
pgskip_dma 0
pgskip_dma32 0
pgskip_normal 0
pgskip_movable 0
pgskip_device 0
pgfree 3077011
pgactivate 0
pgdeactivate 0
pglazyfree 0
pgfault 176973
pgmajfault 488
pglazyfreed 0
pgrefill 0
pgreuse 19230
pgsteal_kswapd 0
pgsteal_direct 0
pgsteal_khugepaged 0
pgdemote_kswapd 0
pgdemote_direct 0
pgdemote_khugepaged 0
pgscan_kswapd 0
pgscan_direct 0
pgscan_khugepaged 0
pgscan_direct_throttle 0
pgscan_anon 0
pgscan_file 0
pgsteal_anon 0
pgsteal_file 0
zone_reclaim_failed 0
pginodesteal 0
slabs_scanned 0
kswapd_inodesteal 0
kswapd_low_wmark_hit_quickly 0
kswapd_high_wmark_hit_quickly 0
pageoutrun 0
pgrotated 0
drop_pagecache 0
drop_slab 0
oom_kill 0
numa_pte_updates 0
numa_huge_pte_updates 0
numa_hint_faults 0
numa_hint_faults_local 0
numa_pages_migrated 0
pgmigrate_success 0
pgmigrate_fail 0
thp_migration_success 0
thp_migration_fail 0
thp_migration_split 0
compact_migrate_scanned 0
compact_free_scanned 0
compact_isolated 0
compact_stall 0
compact_fail 0
compact_success 0
compact_daemon_wake 0
compact_daemon_migrate_scanned 0
compact_daemon_free_scanned 0
htlb_buddy_alloc_success 0
htlb_buddy_alloc_fail 0
cma_alloc_success 0
cma_alloc_fail 0
unevictable_pgs_culled 27002
unevictable_pgs_scanned 0
unevictable_pgs_rescued 744
unevictable_pgs_mlocked 744
unevictable_pgs_munlocked 744
unevictable_pgs_cleared 0
unevictable_pgs_stranded 0
thp_fault_alloc 13
thp_fault_fallback 0
thp_fault_fallback_charge 0
thp_collapse_alloc 4
thp_collapse_alloc_failed 0
thp_file_alloc 0
thp_file_fallback 0
thp_file_fallback_charge 0
thp_file_mapped 0
thp_split_page 0
thp_split_page_failed 0
thp_deferred_split_page 1
thp_split_pmd 1
thp_scan_exceed_none_pte 0
thp_scan_exceed_swap_pte 0
thp_scan_exceed_share_pte 0
thp_split_pud 0
thp_zero_page_alloc 0
thp_zero_page_alloc_failed 0
thp_swpout 0
thp_swpout_fallback 0
balloon_inflate 0
balloon_deflate 0
balloon_migrate 0
swap_ra 0
swap_ra_hit 0
ksm_swpin_copy 0
cow_ksm 0
zswpin 0
zswpout 0
direct_map_level2_splits 29
direct_map_level3_splits 0
nr_unstable 0
EOF
fi

# spoofed /proc/sys/kernel/cap_last_cap
if [[ ! -f "${INSTALL_DIR}/fake/sysctl_entry_cap_last_cap" ]]; then
cat <<- EOF > "${INSTALL_DIR}/fake/sysctl_entry_cap_last_cap"
40
EOF
fi

# spoofed /dev/shm
if [[ ! -d "${INSTALL_DIR}/fake/shm" ]]; then
  mkdir "${INSTALL_DIR}/fake/shm"
  chmod 777 "${INSTALL_DIR}/fake/shm"
fi

# Check if we have our FEX global config dir
if [[ ! -d "${INSTALL_DIR}/FEX" ]]; then
  mkdir "${INSTALL_DIR}/FEX"
  chmod 777 "${INSTALL_DIR}/FEX"
fi

# Check if we have our vulkan dir, if not, get it!
if [[ ! -d "${INSTALL_DIR}/vulkan" ]]; then
  curl -LJ "https://github.com/DesMS/adreno750-drivers/archive/refs/heads/main.zip" -o "${INSTALL_DIR}/vulkan.zip"
  unzip "${INSTALL_DIR}/vulkan.zip" -d "${INSTALL_DIR}"
  mv -f "${INSTALL_DIR}/adreno750-drivers-main" "${INSTALL_DIR}/vulkan"
fi

# Check if we have installed debian
if [[ ! -d "${INSTALL_DIR}/debian-arm64" ]]; then
  echo "Creating debian-arm64"
  # debootstrap results in a much faster root fs than if you get a pre installed one (Idk why)
  debootstrap \
  --variant=minbase \
  --exclude=systemd \
  --arch=arm64 \
  bookworm \
  "${INSTALL_DIR}/debian-arm64" \
  http://ftp.debian.org/debian/
fi

if [[ ! -d "${INSTALL_DIR}/debian-amd64" ]]; then
  echo "Creating debian-amd64"
  # Create our custom debootstrap with x86_64 support
  cp "$(command -v debootstrap)" "${INSTALL_DIR}/debootstrap_x86_64"
  # Use qemu-x86_64 to install it (Will result in an error)
  sed -i 's/proot/proot -q "qemu-x86_64"/g' "${INSTALL_DIR}/debootstrap_x86_64"
  chmod 777 "${INSTALL_DIR}/debootstrap_x86_64"
  # debootstrap results in a much faster root fs than if you get a pre installed one (Idk why)
  "${INSTALL_DIR}/debootstrap_x86_64" \
  --variant=minbase \
  --exclude=systemd \
  --arch=amd64 \
  bookworm \
  "${INSTALL_DIR}/debian-amd64" \
  http://ftp.debian.org/debian/
  # Add our user files (These aren't properly created)
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/passwd"
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
games:x:5:60:games:/usr/games:/usr/sbin/nologin
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
_apt:x:42:65534::/nonexistent:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
main:x:1000:1000:main:/home/main:/bin/bash
EOF
  mkdir "${INSTALL_DIR}/debian-amd64/home/main"
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/group"
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:
dip:x:30:
www-data:x:33:
backup:x:34:
operator:x:37:
list:x:38:
irc:x:39:
src:x:40:
shadow:x:42:
utmp:x:43:
video:x:44:
sasl:x:45:
plugdev:x:46:
staff:x:50:
games:x:60:
users:x:100:
nogroup:x:65534:
main:x:1000:
EOF
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/shadow"
root:*:19839:0:99999:7:::
daemon:*:19839:0:99999:7:::
bin:*:19839:0:99999:7:::
sys:*:19839:0:99999:7:::
sync:*:19839:0:99999:7:::
games:*:19839:0:99999:7:::
man:*:19839:0:99999:7:::
lp:*:19839:0:99999:7:::
mail:*:19839:0:99999:7:::
news:*:19839:0:99999:7:::
uucp:*:19839:0:99999:7:::
proxy:*:19839:0:99999:7:::
www-data:*:19839:0:99999:7:::
backup:*:19839:0:99999:7:::
list:*:19839:0:99999:7:::
irc:*:19839:0:99999:7:::
_apt:*:19839:0:99999:7:::
nobody:*:19839:0:99999:7:::
main:!:19839:0:99999:7:::
EOF
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/gshadow"
root:*::
daemon:*::
bin:*::
sys:*::
adm:*::
tty:*::
disk:*::
lp:*::
mail:*::
news:*::
uucp:*::
man:*::
proxy:*::
kmem:*::
dialout:*::
fax:*::
voice:*::
cdrom:*::
floppy:*::
tape:*::
sudo:*::
audio:*::
dip:*::
www-data:*::
backup:*::
operator:*::
list:*::
irc:*::
src:*::
shadow:*::
utmp:*::
video:*::
sasl:*::
plugdev:*::
staff:*::
games:*::
users:*::
nogroup:*::
main:!::
EOF
  # Create our main user, and add it's bashrc and profile
  if [[ ! -d "${INSTALL_DIR}/debian-amd64/home/main" ]]; then
    mkdir "${INSTALL_DIR}/debian-amd64/home/main"
  fi
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/home/main/.bashrc"
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case \$- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "\$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "\${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=\$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "\$TERM" in
    xterm-color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "\$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "\$color_prompt" = yes ]; then
    PS1='\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ '
else
    PS1='\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "\$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\${debian_chroot:+(\$debian_chroot)}\\u@\\h: \\w\\a\\]\$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "\$(dircolors -b ~/.dircolors)" || eval "\$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "\$([ \$? = 0 ] && echo terminal || echo error)" "\$(history|tail -n1|sed -e '\\''s/^\\s*[0-9]\\+\\s*//;s/[;&|]\\s*alert$//'\\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
EOF
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/home/main/.profile"
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "\$BASH_VERSION" ]; then
  # include .bashrc if it exists
  if [ -f "\$HOME/.bashrc" ]; then
    . "\$HOME/.bashrc"
  fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "\$HOME/bin" ] ; then
  PATH="\$HOME/bin:\$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "\$HOME/.local/bin" ] ; then
  PATH="\$HOME/.local/bin:\$PATH"
fi
EOF
fi

# Check if we have our debug amd64 dir
if [[ ! -d "${INSTALL_DIR}/debian-amd64/debug" ]]; then
  mkdir "${INSTALL_DIR}/debian-amd64/debug"
fi

# Check if we have our debug arm64 dir
if [[ ! -d "${INSTALL_DIR}/debian-arm64/debug" ]]; then
  mkdir "${INSTALL_DIR}/debian-arm64/debug"
fi

# Update arm64 sources.list (For bookworm!)
cat <<- EOF > "${INSTALL_DIR}/debian-arm64/etc/apt/sources.list"
deb http://deb.debian.org/debian bookworm contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-proposed-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-proposed-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-backports contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports contrib main non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
EOF

# Update amd64 sources.list (For bookworm!)
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/apt/sources.list"
deb http://deb.debian.org/debian bookworm contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-proposed-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-proposed-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-backports contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports contrib main non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
EOF

# Add trixie sources for amd64 (For up-to-date packages)
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/apt/sources.list.d/trixie.list"
deb http://deb.debian.org/debian trixie contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-proposed-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-proposed-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-backports contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-backports contrib main non-free non-free-firmware

deb http://deb.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
EOF

# Add trixie sources for arm64 (For up-to-date packages)
cat <<- EOF > "${INSTALL_DIR}/debian-arm64/etc/apt/sources.list.d/trixie.list"
deb http://deb.debian.org/debian trixie contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-proposed-updates contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-proposed-updates contrib main non-free non-free-firmware

deb http://deb.debian.org/debian trixie-backports contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-backports contrib main non-free non-free-firmware

deb http://deb.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
EOF

# This is needed for "libelf1t64" (Required by our custom mesa drivers)
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/etc/apt/sources.list.d/mesa_compatibility.list"
deb http://deb.debian.org/debian sid main
EOF

cat <<- EOF > "${INSTALL_DIR}/debian-arm64/etc/apt/sources.list.d/mesa_compatibility.list"
deb http://deb.debian.org/debian sid main
EOF

# Add our /start_fex.sh script
cat <<- EOF > "${INSTALL_DIR}/debian-arm64/start_fex.sh"
#!/bin/bash
FEXBash
exit \$?
EOF

chmod 777 "${INSTALL_DIR}/debian-arm64/start_fex.sh"

# Check if vulkan is installed
if [[ ! -f "${INSTALL_DIR}/debian-amd64/debug/vulkan_installed" ]]; then
  echo "Setting up vulkan for AMD64"
  # This script reinstalls coreutils and passwd, as it is not installed properly with our wonky debootstrap x86_64 fix
  # This just gets /usr/bin/chown from the package, installs it as our fixed one, then reinstalls coreutils and our fixed passwd packages
  # It then installs vulkan based off of our custom mesa drivers
cat <<- EOF > "${INSTALL_DIR}/debian-amd64/update.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y $APT_ARGS
cd /vulkan
rm -rf /usr/bin/chown
rm -rf /bin/chown
apt download coreutils -y $APT_ARGS
mkdir coreutils
dpkg-deb -xv ./coreutils*amd64.deb ./coreutils
if [[ ! -d "./coreutils/bin" ]]; then
  mkdir ./coreutils/bin
fi
if [[ ! -f "./coreutils/bin/chown" ]]; then
  cp ./coreutils/usr/bin/chown ./coreutils/bin/chown
fi
cp ./coreutils/bin/chown /bin/chown
chmod 777 /bin/chown
cp ./coreutils/bin/chown /usr/bin/chown
chmod 777 /usr/bin/chown
rm -rf ./coreutils
apt upgrade -y $APT_ARGS
apt update -y $APT_ARGS
apt install --reinstall coreutils passwd -y $APT_ARGS
apt install libvulkan1 libvulkan-dev -y $APT_ARGS
apt install ./mesa-vulkan-kgsl_24.1.0-devel-20240422_amd64.deb -y $APT_ARGS
touch /debug/vulkan_installed
EOF
  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -q "qemu-x86_64" -w "/root" -r "${INSTALL_DIR}/debian-amd64" -i "0" $ARGS \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=/root" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash /update.sh
  rm -rf "${INSTALL_DIR}/debian-amd64/update.sh"
fi

# Check if vulkan is installed for arm64
if [[ ! -f "${INSTALL_DIR}/debian-arm64/debug/vulkan_installed" ]]; then
  echo "Setting up vulkan for ARM64"
  # This script reinstalls coreutils and passwd, just to make sure they're installed correctly in the first place
  # It then installs vulkan based off of our custom mesa drivers
cat <<- EOF > "${INSTALL_DIR}/debian-arm64/update.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y $APT_ARGS
cd /vulkan
rm -rf /usr/bin/chown
rm -rf /bin/chown
apt download coreutils -y $APT_ARGS
mkdir coreutils
dpkg-deb -xv ./coreutils*arm64.deb ./coreutils
if [[ ! -d "./coreutils/bin" ]]; then
  mkdir ./coreutils/bin
fi
if [[ ! -f "./coreutils/bin/chown" ]]; then
  cp ./coreutils/usr/bin/chown ./coreutils/bin/chown
fi
cp ./coreutils/bin/chown /bin/chown
chmod 777 /bin/chown
cp ./coreutils/bin/chown /usr/bin/chown
chmod 777 /usr/bin/chown
rm -rf ./coreutils
apt upgrade -y $APT_ARGS
apt update -y $APT_ARGS
apt install --reinstall coreutils passwd -y $APT_ARGS
apt install ./libvulkan1_1.3.250.0-1_arm64.deb ./libvulkan-dev_1.3.250.0-1_arm64.deb -y $APT_ARGS
apt install ./mesa-vulkan-kgsl_24.1.0-devel-20240421_arm64.deb -y $APT_ARGS
touch /debug/vulkan_installed
EOF
  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -w "/root" -r "${INSTALL_DIR}/debian-arm64" -i "0" $ARGS \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=/root" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash /update.sh
  rm -rf "${INSTALL_DIR}/debian-arm64/update.sh"
fi

# Check if fex is installed, or if the user wants to install it manually
if [[ ! -f "${INSTALL_DIR}/debian-arm64/debug/fex_installed" || "$1" == "update" ]]; then
  echo "Building and installing fex"
  rm -rf "${INSTALL_DIR}/debian-arm64/fex-install" &>/dev/null # Prevent directory is already there error
  # It is much faster if we git clone out here, rather than in the proot environment
  git clone --recurse-submodules https://github.com/FEX-Emu/FEX.git "${INSTALL_DIR}/debian-arm64/fex-install"
  # Apply CPU spoof
  sed -i "$(grep -m1 -n "\"model name\\\\t:" "${INSTALL_DIR}/debian-arm64/fex-install/Source/Tools/LinuxEmulation/LinuxSyscalls/EmulatedFiles/EmulatedFiles.cpp" | cut -d: -f1)s/.*/cpu_stream << \"model name\\\\t: ${CPU_MODEL}\" << std::endl;/" "${INSTALL_DIR}/debian-arm64/fex-install/Source/Tools/LinuxEmulation/LinuxSyscalls/EmulatedFiles/EmulatedFiles.cpp"
cat <<- EOF > "${INSTALL_DIR}/debian-arm64/install_fex.sh"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y $APT_ARGS
apt install apt-utils -y
apt install g++-multilib-i686-linux-gnu gcc-multilib-i686-linux-gnu g++-multilib-x86-64-linux-gnu gcc-multilib-x86-64-linux-gnu git cmake ninja-build pkgconf ccache clang llvm lld libdrm-dev libxcb-present-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-glx0-dev libxcb-shm0-dev pkg-config libxshmfence-dev libclang-dev libsdl2-dev libepoxy-dev libssl-dev g++-x86-64-linux-gnu libgcc-12-dev-i386-cross libgcc-12-dev-amd64-cross nasm python3-clang libstdc++-12-dev-i386-cross libstdc++-12-dev-amd64-cross libstdc++-12-dev-arm64-cross squashfs-tools libc6-dev-i386-amd64-cross lib32stdc++-12-dev-amd64-cross libc-bin -y $APT_ARGS
cd /fex-install
mkdir Build
cd Build
CC=clang CXX=clang++ cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True -DBUILD_TESTS=False -DENABLE_ASSERTIONS=False -DBUILD_THUNKS=True -G Ninja ..
ninja
ninja install
cd /
rm -rf /fex-install
chmod 777 /start_fex.sh
touch /debug/fex_installed
EOF
  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -w "/root" -r "${INSTALL_DIR}/debian-arm64" -i "0" $ARGS \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=/root" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash /install_fex.sh
  # Fix our RootFS
cat <<- EOF > "${INSTALL_DIR}/FEX/Config.json"
{"Config": {"RootFS": "Debian_Bookworm"}}
EOF
  rm -rf "${INSTALL_DIR}/debian-arm64/install_fex.sh"
fi

# Check if we need to have a user, or if we need to set a user
if [[ ! -z "$1" ]]; then
  if [[ "$1" != "x11" && "$1" != "gl" && "$1" != "opengl" && "$1" != "update" ]]; then
    if [[ -z "$2" ]]; then
      echo "Chose user \"root\""
      export HOME_PROOT="/root"
      export USER_ID_PROOT="0"
    else
      export USER_PROOT="${2,,}"
      if [[ "$USER_PROOT" == "root" ]]; then
        echo "Chose user \"root\""
        export HOME_PROOT="/root"
        export USER_ID_PROOT="0"
      elif [[ "$USER_PROOT" == "main" ]]; then
        echo "Chose user \"main\""
        export HOME_PROOT="/home/main"
        export USER_ID_PROOT="1000"
      else
        print_usage
        exit 0
      fi
    fi
  fi
fi

# These all start it, it is quite self explanatory from now on
if [[ "$1" == "qemu" ]]; then
  start_x

  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -q "qemu-x86_64" -w "$HOME_PROOT" -r "${INSTALL_DIR}/debian-amd64" -i "$USER_ID_PROOT" $ARGS \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=${HOME_PROOT}" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash --login
elif [[ "$1" == "x11" || "$1" == "gl" || "$1" == "opengl" ]]; then
  start_x
elif [[ "$1" == "fex" ]]; then
  start_x

  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -w "$HOME_PROOT" -r "${INSTALL_DIR}/debian-arm64" -i "$USER_ID_PROOT" $ARGS -b "${INSTALL_DIR}/start_fex.sh:/start_fex.sh" \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=${HOME_PROOT}" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash -c /start_fex.sh
elif [[ "$1" == "none" ]]; then
  start_x

  unset LD_PRELOAD
  proot --link2symlink --kill-on-exit -L -w "$HOME_PROOT" -r "${INSTALL_DIR}/debian-arm64" -i "$USER_ID_PROOT" $ARGS \
  /usr/bin/env -i \
  "GALLIUM_DRIVER=virpipe" \
  "DISPLAY=:0" \
  "MESA_VK_WSI_DEBUG=sw" \
  "TU_DEBUG=noconform" \
  "LANG=C.UTF-8" \
  "HOME=${HOME_PROOT}" \
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "TMPDIR=/tmp" \
  "PULSE_SERVER=127.0.0.1" \
  "MOZ_FAKE_NO_SANDBOX=1" \
  "TERM=${TERM-xterm-256color}" \
  /bin/bash --login
elif [[ "$1" != "update" ]]; then
  print_usage
fi

exit 0
