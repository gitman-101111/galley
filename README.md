# galley
AOSP "Kitchen" for Docker; primarily created for building custom GrapheneOS builds

# Getting Started
1. `git clone https://github.com/gitman-101111/galley` && `cd galley`
2. Modify docker-compose.yml and build.sh (for any mods, etc.) to your liking
3. `docker-compose -f docker-compose.yml up -d`
4. `docker logs the-galley # To monitor progress...`

Thanks to the GrapheneOS project, Magisk (https://github.com/topjohnwu/Magisk), and AVBRoot (https://github.com/chenxiaolong/avbroot)
