#!/bin/bash
set -e # Quit on error

export WORKDIR=$OS
export OUT_DIR=out
export BUILD_NUMBER=$(date +%Y%m%d01)
export TARGET_RELEASE=$(echo $GOOGLE_BUILD_ID |  tr '[:upper:]' '[:lower:]'| cut -d. -f1)
export RED='\033[0;31m'
export GREEN='\033[0;33m'
export BLUE='\033[0;36m'
export NC='\033[0m'

echo -e "${NC}
           ===                                ===
            ===                              ===
              ===                            ==
                ==       ============       ==
               ============================
              ==============================
           ====================================
         ========================================
        ============================================
       ==============================================
      =========    ======================    =========
     ==========    ======================    ==========
    ============  ========================  ============
   ======================================================
  ========================================================
  ========================================================
  ========================================================

                           WELCOME
\n\n"
#printf USR=$USR\\nGRP=$GRP\\nOS=$OS\\nTGT=$TGT\\nTAG=$TAG\\nGOOGLE_BUILD_ID=$GOOGLE_BUILD_ID\\nVERSION=$VERSION\\nUPDATE_URL=$UPDATE_URL\\nOFFICIAL_BUILD=$OFFICIAL_BUILD\\nREBUILD=$REBUILD\\nPUSH=$PU>
if [[ $TGT == "" ]]; then
    echo -e "${RED}No target set ${NC}"
    exit
else
    IFS=', ' read -r -a targets <<< $(echo "$TGT" | tr '[:upper:]' '[:lower:]')
    echo -e "${GREEN}Targets: ${targets[*]} ${NC}\n"
fi

OPTSTRING="fuckersh"
while getopts ${OPTSTRING} opt; do
  case ${opt} in
    f)
      KERNEL=true
      ;;
    u)
      AAPT2=true
      ;;
    c)
      CUSTOMIZE=true
      ;;
    k)
      KEYS=true
      ;;
    e)
      EXTRACT=true
      ;;
    r)
      ROM=true
      ;;
    s)
      SYNC=true
      ;;
    h)
      HELP="
        -h: This help message :-)
        [Nothing]: If no arguments are passed, all steps run (default when run in a docker container)! 
        -s: Default: False; Sync the repo with the tag passed
        -u: Default: False; Build aapt2 if not using a prebuilt verison
        -e: Default: False; Extract vendor files from the latest Google OTA/Factory images
        -c: Default: False; Whether or not to apply patches to customize your build
        -k: Default: False; Generate/move keys from "/build_mods/keys/'$target'"
        -r: Default: False; Build the rom!
      "
      echo $HELP
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done
if [[ $# -eq 0 ]]; then
  echo "No args detected, assuming defaults"
  # echo $HELP
  AAPT2=true
  CUSTOMIZE=true
  KEYS=true
  EXTRACT=true
  ROM=true
  SYNC=true
  KERNEL=false
  ROOT_TYPE="magisk"
fi

# https://github.com/cawilliamson/rooted-graphene
function repo_sync_until_success() {
  # (using -j4 makes the sync less likely to hit rate limiting)
  until repo sync -c -j4 --fail-fast --no-clone-bundle --no-tags --force-sync; do
    echo "repo sync failed, retrying in 1 minute..."
    sleep 60
  done
}

# Set git opts
git config --global user.email "user@domain.com"
git config --global user.name "user"
git config --global color.ui true

# Setup our dirs
if [[ -e /src/$WORKDIR ]]; then
    echo -e "${GREEN}/src/$WORKDIR exists, skipping creation ${NC}"
    if [[ "$OFFICIAL_BUILD" == true ]]; then
        if [ "$AAPT2" == true ] && [ "$ROM" == true ]; then
          echo -e "${RED}Official build detected, cleaning /src/$WORKDIR/$OUT_DIR ${NC}"
          rm -rf /src/$WORKDIR/$OUT_DIR
          mkdir /src/$WORKDIR/$OUT_DIR
        fi
    fi
else
    echo -e "${RED} /src/$WORKDIR/ not found, creating ${NC}"
    mkdir /src/$WORKDIR
    sudo chown -R $USR:$GRP /src/$WORKDIR
fi
cd /src/$WORKDIR

# Set perms
echo -e "${GREEN}Setting permissions...${NC}"
sudo chown -R $USR:$GRP /src
sudo chown -R $USR:$GRP /build_mods

# Figure out what we're doing
if [[ "$TAG" =~ ^[0-9]{10}$ ]]; then
    echo -e "${GREEN}Release branch tag detected! ${NC}"
    repo init -u https://github.com/GrapheneOS/platform_manifest.git -b $TAG

    # Verify
    curl https://grapheneos.org/allowed_signers > /tmp/grapheneos_allowed_signers
    cd .repo/manifests
    git config gpg.ssh.allowedSignersFile /tmp/grapheneos_allowed_signers
    git verify-tag $(git describe)
    cd /src/$WORKDIR
else
    echo -e "${GREEN}Dev branch tag detected! ${NC}"
    repo init -u https://github.com/GrapheneOS/platform_manifest.git -b $TAG
fi

if [[ "$SYNC" == true ]]; then
  # Undo patches before sync
  echo -e "${BLUE}Undoing patches prior to sync"
  cd /src/$WORKDIR/.repo/repo && git reset --hard && git clean -ffdx
  repo forall -vc "git reset --hard"

  # Update repo
  sudo apt upgrade repo -y

  cd /src/$WORKDIR
  repo sync --force-sync
  #repo_sync_until_success

  # If stuff couldn't be synced (packages/Updater, build/make/target/product)
  # Delete and then restore deleted files!? ex.
  # repo forall build/make/target/product/ -c 'git checkout .'
fi

# Build Kernel
if [ "$KERNEL" == true ] || [ "$ROOT_TYPE" == "kernelsu" ]; then
  if [[ -e /src/kernel ]]; then
    echo -e "${RED}Cleaning /src/kernel/*${NC}"
    rm -rf /src/kernel/*
  fi
  for target in "${targets[@]}"
  do
    if [ "$target" == "husky" ] || [ "$target" == "shiba" ]; then
      export KTGT="shusky"
      export MTGT="zuma"
      export BRANCH=$VERSION
      export KVER="6.1"
    fi
    if [ "$target" == "caiman" ] || [ "$target" == "komodo" ] || [ "$target" == "tokay" ]; then
      export KTGT="caimito"
      export MTGT="$KTGT"
      export BRANCH="$VERSION-$KTGT"
      export KVER="6.1"
    fi
    if [ "$target" == "tangorpro" ]; then
      export KTGT="tangorpro"
      export MTGT="gs"
      export BRANCH="$VERSION"
      export KVER="6.1"
    fi
    if [[ ! -e /src/kernel/$KTGT ]]; then
      mkdir -p /src/kernel/$KTGT
    fi
    cd /src/kernel/$KTGT
    repo init -u https://github.com/GrapheneOS/kernel_manifest-$MTGT.git -b $BRANCH
    repo_sync_until_success
    # repo init -u https://github.com/GrapheneOS/kernel_manifest-shusky.git -b "refs/tags/$T" --depth=1 --git-lfs

    # MOD IT
    if [[ "$ROOT_TYPE" == "kernelsu" ]]; then
      # Root via KernelSU
      cd /src/kernel/$KTGT/aosp
      curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
      cd /src/kernel/$KTGT
    fi

    # BUILD IT
    if [ "$target" == "caiman" ] || [ "$target" == "komodo" ] || [ "$target" == "tokay" ] || [ "$target" == "comet" ] || [ "$target" == "shiba" ] || [ "$target" == "husky" ]; then
      ./build_$KTGT.sh --config=use_source_tree_aosp --config=no_download_gki --lto=full
      # Apparently the build script moves it on its own...?
      cp -R /src/kernel/$KTGT/out/$KTGT/dist /src/$WORKDIR/device/google/$KTGT-kernels/$KVER/24D1/
    fi
    if [ "$target" == "tangorpro" ]; then
      BUILD_AOSP_KERNEL=1 LTO=full ./build_$KTGT.sh
    fi
    cd /src/$WORKDIR
  done
fi

if [[ "$ROOT_TYPE" == "magisk" ]]; then
    # AVBRoot
    if [[ -e /build_mods/avbroot ]]; then
      echo -e "${GREEN}avbroot module exists, not cloning ${NC}"
      else
      mkdir /build_mods/avbroot
    fi
    echo -e "${RED}Grabbing latest avbroot module ${NC}"
    export avblatestver=$(echo -e "$(curl https://api.github.com/repos/chenxiaolong/avbroot/releases/latest -s | jq .name -r)" | sed 's/Version//g')
    export avblink=$(echo -e "https://github.com/chenxiaolong/avbroot/releases/latest/download/avbroot-$avblatestver-x86_64-unknown-linux-gnu.zip" | sed 's/ //g')
    wget $avblink -O /build_mods/avbroot/avbroot.zip
    unzip -o /build_mods/avbroot/avbroot.zip -d /build_mods/avbroot/
    chmod +x /build_mods/avbroot/avbroot

    # Magisk
    echo -e "${RED}Grabbing latest Magisk zip ${NC}"
    export magiskapk=$(echo -e "$(curl https://api.github.com/repos/topjohnwu/Magisk/releases/latest -s | jq .name -r).apk" | sed 's/ /-/g')
    wget https://github.com/topjohnwu/Magisk/releases/latest/download/$magiskapk -O /build_mods/avbroot/Magisk.apk
    #wget https://github.com/topjohnwu/Magisk/releases/latest/download/app-release.apk -O /build_mods/avbroot/Magisk.apk
fi

if [[ "$AAPT2" == true ]]; then
  echo -e "${GREEN}Installing adevtool ${NC}"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0 && yarn install --cwd vendor/adevtool/ 
  # yarnpkg install --cwd vendor/adevtool/
  source /src/$WORKDIR/build/envsetup.sh
  echo -e "${GREEN}Compiling aapt2 ${NC}"
  lunch sdk_phone64_x86_64-cur-user
  m arsclib
  if [[ -s $OUT_DIR/error.log ]]; then
      echo -e "${RED}aapt2 compile failed! ${NC}"
      apprise -t "The Galley" -b "aapt2 build failed!" $APPRISE_CONFIG
  else
      echo -e "${GREEN}aapt2 compiled successfully! ${NC}"
      apprise -t "The Galley" -b "aapt2 build completed successfully!" $APPRISE_CONFIG
  fi
fi

if [[ "$EXTRACT" == true ]]; then
  # export target=""
  for target in "${targets[@]}"
  do
    # Extract vendor files
    clear
    echo -e "${GREEN}Downloading and extracting vendor files for $target ${NC}"
    ./vendor/adevtool/bin/run generate-all -d $target
  done
  # echo -e "${GREEN}Vendor files for ${targets} downloaded!"
fi

if [[ "$CUSTOMIZE" == true ]]; then
  ## PRE-BUILD MODS (ALL TARGETS) ##
  apprise -t "The Galley" -b "Applying pre-build mods" $APPRISE_CONFIG

  # Custom hosts for some OOTB adblocking
  echo -e "${BLUE}Modifying hosts file ${NC}"
  curl https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o system/core/rootdir/etc/hosts

  # Copy over additional prebuilts
  # export gmscore=$(echo -e "$(curl https://api.github.com/repos/microg/GmsCore/releases/latest -s | jq .name -r)")    
  # apksigner sign --key /build_mods/fs-verity/key.pk8 --cert /build_mods/fs-verity/cert.pem GmsCore.apk
  # echo -e "${BLUE}Injecting GmsCore ${NC}"
  # cp -r /build_mods/external/GmsCore /src/$WORKDIR/external/
  # md5sum /src/$WORKDIR/external/GmsCore/GmsCore.apk

  # Copy custom boot animation
  echo -e "${BLUE}Replacing bootanimation ${NC}"
  cp /build_mods/bootanimation.zip frameworks/base/data/

  # Copy custom notification sound (and set perms)
  echo -e "${BLUE}Copying custom notification sounds and setting permissions ${NC}"
  cp /build_mods/fasten_seatbelt.ogg frameworks/base/data/sounds/notifications/
  chmod 644 frameworks/base/data/sounds/notifications/fasten_seatbelt.ogg
  # patching will be handled by frameworks-base-patches-14.patch

  # Patch it up
  echo -e "${RED}Applying frameworks/base patch to build ${NC}"
  git apply --directory="/src/$WORKDIR/frameworks/base" --unsafe-paths "/build_mods/patches/$VERSION/frameworks-base-patches-$VERSION.patch"
  if [ $? -ne 0 ]; then
      # there was an error
      echo -e "${RED}git apply of frameworks/base patch failed ${NC}"
  else
      echo -e "${GREEN}frameworks/base patches successfully applied ${NC}"
  fi

  echo -e "${RED}Applying build/make patch to build ${NC}"
  git apply --directory="/src/$WORKDIR/build/make" --unsafe-paths "/build_mods/patches/$VERSION/build-make-patches-$VERSION.patch"
  if [ $? -ne 0 ]; then
      # there was an error
      echo -e "${RED}git apply of build/make patch failed ${NC}"
  else
      echo -e "${GREEN}build/make patches successfully applied ${NC}"
  fi
  # cd /src/$WORKDIR/
  # read -n 1 -p "Patches applied; Press any key to continue..."

  # Setup updates
cat << EOF > packages/apps/Updater/res/values/config.xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
<string name="url" translatable="false">$UPDATE_URL</string>
<string name="channel_default" translatable="false">stable</string>
<string name="network_type_default" translatable="false">1</string>
<string name="battery_not_low_default" translatable="false">true</string>
<string name="requires_charging_default" translatable="false">false</string>
<string name="idle_reboot_default" translatable="false">false</string>
</resources>
EOF

  apprise -t "The Galley" -b "Pre-build mods applied!" $APPRISE_CONFIG
fi

if [[ "$KEYS" == true ]]; then
  for target in "${targets[@]}"
  do
      if [[ -e /build_mods/keys/$target ]]; then
          if [[ -e /src/$WORKDIR/keys/$target ]]; then
              echo -e "${RED}Key directory exists for $target, not recreating or replacing! ${NC}"
          else
              echo -e "${BLUE}Copying keys for $target from build_mods ${NC}"
              mkdir -p /src/$WORKDIR/keys/$target
              cp -R /build_mods/keys/$target /src/$WORKDIR/keys/ 
          fi
      fi

      # Generate keys & sign & encrypt
      if [[ -e /src/$WORKDIR/keys/$target ]]; then
        if [[ $(ls /src/$WORKDIR/keys/$target/*.pk8 -l | wc -l) -ge 7 ]]; then
            echo -e "${GREEN}Keys for $target exist, skipping recreation ${NC}"
        fi
        if [[ -e /src/$WORKDIR/keys/$target/avb.pem ]]; then
            echo -e "${GREEN}AVB key exists for $target ${NC}"
        else
            openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out /src/$WORKDIR/keys/$target/avb.pem
        fi
        if [[ -e /src/$WORKDIR/keys/$target/avb_pkmd.bin ]]; then
            echo -e "${GREEN}Public key exists for $target ${NC}"
        else
            /src/$WORKDIR/external/avb/avbtool.py extract_public_key --key /src/$WORKDIR/keys/$target/avb.pem --output /src/$WORKDIR/keys/$target/avb_pkmd.bin
        fi
        if [[ -e /src/$WORKDIR/keys/$target/factory.sec ]]; then
            echo -e "${GREEN}Factory key exists for $target ${NC}"
        fi
      else
        mkdir -p /src/$WORKDIR/keys/$target
        cd /src/$WORKDIR/keys/$target
        printf "\n" | /src/$WORKDIR/development/tools/make_key releasekey '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key platform '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key shared '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key media '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key networkstack '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key sdk_sandbox '/CN=$CN/'
        printf "\n" | /src/$WORKDIR/development/tools/make_key bluetooth '/CN=$CN/'
        openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out /src/$WORKDIR/keys/$target/avb.pem -passout pass:""
        #TODO Maybe run an expect...prompts here?
        /src/$WORKDIR/external/avb/avbtool.py extract_public_key --key /src/$WORKDIR/keys/$target/avb.pem --output /src/$WORKDIR/keys/$target/avb_pkmd.bin
        cd /src/$WORKDIR
        signify -G -n -p/src/$WORKDIR/keys/$target/factory.pub -s/src/$WORKDIR/keys/$target/factory.sec
        # signify-openbsd -G -n -p/src/$WORKDIR/keys/$target/factory.pub -s/src/$WORKDIR/keys/$target/factory.sec
        #TODO And here..?
        /src/$WORKDIR/script/encrypt-keys.sh /src/$WORKDIR/keys/$target
        cp -R /src/$WORKDIR/keys/$target /build_mods/keys/$target
      fi

      # Gen keys for root
      if [[ -e /src/$WORKDIR/keys/$target/avb.key ]]; then
          echo -e "${RED}AVB key exists, continuing ${NC}"
      else
          /src/$WORKDIR/script/decrypt-keys.sh /src/$WORKDIR/keys/$target
          # openssl rsa -outform der -in /src/$WORKDIR/keys/$target/avb.pem -out /src/$WORKDIR/keys/$target/avb_python.key
          # cp /src/$WORKDIR/keys/$target/avb_python.key /src/$WORKDIR/keys/$target/ota_python.key
          cp /src/$WORKDIR/keys/$target/avb.pem /src/$WORKDIR/keys/$target/avb.key
          cp /src/$WORKDIR/keys/$target/avb.key /src/$WORKDIR/keys/$target/ota.key
          /build_mods/avbroot/avbroot key extract-avb -k /src/$WORKDIR/keys/$target/avb.key --output /src/$WORKDIR/keys/$target/avb_pkmd.bin
          openssl req -new -x509 -sha256 -key /src/$WORKDIR/keys/$target/ota.key -out /src/$WORKDIR/keys/$target/ota.crt -days 10000 -subj /CN=$CN/
          cp /src/$WORKDIR/keys/$target/avb.key /build_mods/keys/$target/
      fi
  done

  ## ADD FS-VERITY KEYS ##
  if [[ -e /build_mods/fs-verity/fsverity_cert.0.der ]]; then
      echo -e "${BLUE}fs-verity keys exist, not recreating ${NC}"
      cp /build_mods/fs-verity/fsverity_cert.0.der /src/$WORKDIR/build/make/target/product/security/
      git apply --directory="/src/$WORKDIR/build/make" --unsafe-paths /build_mods/fs-verity/fs-verity-$VERSION.patch
      if [ $? -ne 0 ]; then echo "Patch NOT applied"; fi
    else
      echo -e "${RED}fs-verity keys not found, creating ${NC}"
      openssl req -newkey rsa:4096 -sha512 -noenc -keyout /build_mods/fs-verity/fsverify_private_key.0.pem -x509 -out /build_mods/fs-verity/fsverity_cert.0.pem -days 10000 -subj /CN=$CN/
      openssl x509 -in /build_mods/fs-verity/fsverity_cert.0.pem -out /build_mods/fs-verity/fsverity_cert.0.der -outform der
      # to sign...
      # fsverity sign app-release.apk app-release.apk.fsv_sig --key fsverity_private_key.0.pem --cert fsverity_cert.0.pem
      cp /build_mods/fs-verity/fsverity_cert.0.der /src/$WORKDIR/build/make/target/product/security/
      git apply --directory="/src/$WORKDIR/build/make" --unsafe-paths /build_mods/fs-verity/fs-verity-$VERSION.patch
      if [ $? -ne 0 ]; then echo "Patch NOT applied"; fi
  fi
fi

if [ "$ROM" == true ]; then
  echo "ROM is true"
  echo "{$targets[*]}"

  for target in "${targets[@]}"
  do
    apprise -t "The Galley" -b "Building for $target at $(date)" $APPRISE_CONFIG

    # Build it
    source /src/$WORKDIR/build/envsetup.sh
    lunch $target-$TARGET_RELEASE-user
    m vendorbootimage vendorkernelbootimage target-files-package
    if [[ -s $OUT_DIR/error.log ]]; then
        apprise -t "The Galley" -b "Build failed for $target!" $APPRISE_CONFIG
        exit 2
    else
        apprise -t "The Galley" -b "Build for $target completed successfully!" $APPRISE_CONFIG
    fi

    # Generate OTA stuff
    m otatools-package
    if [[ -s $OUT_DIR/error.log ]]; then
        apprise -t "The Galley" -b "OTA Tools failed for $target!" $APPRISE_CONFIG
        exit 2
    else
        apprise -t "The Galley" -b "OTA Tools for $target packaged successfully!" $APPRISE_CONFIG
    fi

    # Sign and package...
    # if passphrase=""...
    script/finalize.sh
    if [ "$CERTPASS" == "" ]; then
      printf "\n" | script/generate-release.sh $target $BUILD_NUMBER
    else
      echo "{RED}Need CERTPASS handled, unable to continue ${NC}"
      # exit 1
    fi
    apprise -t "The Galley" -b "Release signed and packaged for $target!" $APPRISE_CONFIG

    if [[ "$ROOT_TYPE" == "magisk" ]]; then
      if [[ "$target" == "tangorpro" ]]; then
          echo -e "${RED}Tangorpro detected ${NC}"
          export preinit=sda5 #(not sda5t...?)
      elif [[ "$target" == "caiman" ]]; then
          echo -e "${RED}Caiman detected ${NC}"
          export preinit=sda10
      fi

      # Ensure we're in a good place to gen up (pre-rooted) incremental updates in the future
      # Actually patch the ota
      /build_mods/avbroot/avbroot patch --input /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-*.zip --privkey-avb /src/$WORKDIR/keys/$target/avb.key --privkey-ota /src/$WORKDIR/keys/$target/ota.key --pass-avb-env-var PASSPHRASE_AVB --pass-ota-env-var PASSPHRASE_OTA --cert-ota /src/$WORKDIR/keys/$target/ota.crt --magisk /build_mods/avbroot/Magisk.apk --magisk-preinit-device $preinit --ignore-magisk-warnings
      # Setup a temp directory ("./root")
      mkdir -p /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/root
      # Extract to the temp directory & enter
      /build_mods/avbroot/avbroot ota extract --input /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-*.zip.patched --directory /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/root/
      cd /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/
      # Extract the factory zip into "./factory"
      unzip -j $target-factory-*.zip -d factory
      # Inject the patched images into the images zip
      zip factory/image-$target-*.zip -j root/*
      # Keys are identical, md5s match last I checked
      # zip /src/$WORKDIR/keys/$target/avb_pkmd.bin $target-factory-*/image-$target-*.zip
      # Inject the now patched image zip into the factory zip
      zip factory/image-$target-*.zip $target-factory*.zip
      # Remove the temp directory
      rm -rf root/
      # Append ".unpatched" to the untouched ota zip
      mv /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-$BUILD_NUMBER.zip /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-$BUILD_NUMBER.zip.unpatched
      # Append ".patched" to the patched ota zip
      mv /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-$BUILD_NUMBER.zip.patched /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-ota_update-$BUILD_NUMBER.zip
      cd /src/$WORKDIR/
    fi

    # Fin
    echo -e "${RED}Built $OUT_DIR/release-$target-$BUILD_NUMBER ${NC}"

    # PUSH TO UPDATE SERVER
    if [[ "$PUSH" == true ]]; then

      # Create list of files to be pushed to the update server
      if [[ ! -f /src/$WORKDIR/releases/filesToPushToUpdateServer.txt ]]; then
        touch /src/$WORKDIR/releases/filesToPushToUpdateServer.txt
      fi

      # Add targets to the list
      if [[ $(grep -R $target "/src/$WORKDIR/releases/filesToPushToUpdateServer.txt") == true ]]; then
        echo -e "${RED}$target found, skipping${NC}"
      else
        echo -e "$target-ota_update-$BUILD_NUMBER.zip\n$target-factory-$BUILD_NUMBER.zip\n$target-factory-$BUILD_NUMBER.zip.sig\n$target-testing\n$target-beta\n$target-stable\n" >> /src/$WORKDIR/releases/filesToPushToUpdateServer.txt
      fi

      echo -e "

      # If running from working directory of container where "src" is present...
      rsync -av --files-from=src/$WORKDIR/releases/filesToPushToUpdateServer.txt --no-relative src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/ $RSYNC_TARGET

      "
      apprise -t "The Galley" -b "Ready to be pushed!" $APPRISE_CONFIG
    fi

    if [[ -e /src/$WORKDIR/releases/$BUILD_NUMBER/release-$target-$BUILD_NUMBER/$target-factory-$BUILD_NUMBER.zip ]]; then
      apprise -t "The Galley" -b "Factory image ready for $target at $(date)" $APPRISE_CONFIG
    fi
  done
fi
