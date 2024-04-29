# Termux-FEX
FEX for termux

## How to run

```sh
curl -LJ "https://github.com/DesMS/Termux-FEX/raw/main/start.sh" -o ./start.sh
chmod 777 ./start.sh
./start.sh fex main
```

## Usage:

```txt
Usage: ./start.sh feature [user]


Available Features:
[qemu] - Start a x86_64 environment using proot with qemu-x86_64 (Use this for modifying the x86_64 filesystem)
[x11, gl, opengl] - Only start the x11 server and OpenGL server (Recommended if you're switching between methods alot)
[fex] - Start a x86_64 environment using proot with FEX (Recommended for performance, use qemu for modifying the filesystem)
[update] - Update FEX to it's latest version and pass new args to it (User arg is ignored)
[none] - Start a arm64 environment for the FEX filesystem (Recommended for building)

Available Users:
[root] - The root user (Not recommended with FEX)
[main] - A user with sudo privileges (Sudo does not work with FEX)
If no user is chosen, it will default to "root"
```

## Environment Variables Configuration:

#### `CPU_MODEL`:

The spoofed CPU model for when you're running FEX (Defaults to `Qualcomm Snapdragon 8 Gen 3`).

For example, if you want to set your CPU model to `Qualcomm Snapdragon 8 Gen 3 for Galaxy`, you would do:

```sh
CPU_MODEL="Qualcomm Snapdragon 8 Gen 3 for Galaxy" ./start.sh update
```

then, you can run it like normal with the spoofed CPU name

#### `INSTALL_DIR`:

The place where everything gets installed into. This will create a new installation, and won't delete your old one

For example, if you want to install to `${HOME}/fex_emu`, you can do:

```sh
INSTALL_DIR="${HOME}/fex_emu" ./start.sh fex main
```

#### `DIRECTORIES`:

This is if you want to share directories from your host filesystem, to your guest filesystems (Shares to both your x86_64 and ARM64 guest filesystems)

For example, if you want to share `${HOME}/games` to `/games`, you can do:

```sh
DIRECTORIES="${HOME}/games:/games" ./start.sh fex main
```

Or, if you want to share `${HOME}/games` to `/games` and `${HOME}/downloads` to `/games/downloads`, you can do:

```sh
DIRECTORIES="${HOME}/games:/games
${HOME}/downloads:/games/downloads" ./start.sh fex main
```

Empty lines are automatically omitted, so you can do:

```sh
DIRECTORIES="
${HOME}/games:/games



${HOME}/downloads:/games/downloads" ./start.sh fex main
```

Format:

`{SOURCE_DIRECTORY}` `:` `{OUTPUT_DIRECTORY}`

#### `SHARED_DIRECTORIES`:

This is for when you want to share files/directories from your **AMD64** filesystem to your **ARM64** filesystem

For example, if you want to share `/mygamesave` between the 2, you can do:

```sh
SHARED_DIRECTORIES="/mygamesave" ./start.sh none main
```

This is the same as `DIRECTORIES`, in that you use newlines to seperate them, but you don't use the same format, all you have to do is enter the path

## Notes

* This will use ~6gB (~6342083kB) of storage as of 04/29/2024. This may change between updates and between different days, due to debian updating their packages.
* Currently, only Debian is supported, but in the future this may be expanded to include Ubuntu
* NEVER TRY AND MODIFY YOUR AMD64 FILESYSTEM WHEN IN FEX (THIS IS NOT A ISSUE WITH THIS REPO, ITS AN ISSUE WITH FEX)
* The CPU spoof doesn't work 100% of the time, and sometimes doesn't get applied

## Compatibility

| Tested Device | CPU | GPU | Supported | Vulkan Supported |
| -- | -- | -- | -- | -- |
| Samsung Galaxy™ S24 | Qualcomm® Snapdragon™ 8 Gen 3 for Galaxy | Qualcomm® Adreno™ 750 | :white_check_mark: | :white_check_mark: |
| Samsung Galaxy™ S23 | Qualcomm® Snapdragon™ 8 Gen 2 | Qualcomm® Adreno™ 740 | :white_check_mark: | :grey_question: |
