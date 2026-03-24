{%- if grains['id'] != 'dom0' %}

makemkv-dom0-only:
  test.fail_without_changes:
    - name: "This state must only run on dom0 via: qubesctl --skip-dom0 ... will not help here - run without --skip-dom0"

{%- else %}

{%- set vm      = salt['pillar.get']('makemkv:appvm:name',            'makemkv') %}
{%- set tmpl    = salt['pillar.get']('makemkv:appvm:template',        'debian-13-xfce') %}
{%- set label   = salt['pillar.get']('makemkv:appvm:label',           'orange') %}
{%- set memory  = salt['pillar.get']('makemkv:appvm:memory',          3092) %}
{%- set maxmem  = salt['pillar.get']('makemkv:appvm:maxmem',          0) %}
{%- set vcpus   = salt['pillar.get']('makemkv:appvm:vcpus',           2) %}
{%- set storage = salt['pillar.get']('makemkv:appvm:private_storage', 20480) %}

# ---------------------------------------------------------------------------
# 1. Create the AppVM
# ---------------------------------------------------------------------------

makemkv-create-appvm:
  qvm.present:
    - name: {{ vm }}
    - template: {{ tmpl }}
    - label: {{ label }}
    - class: AppVM

makemkv-appvm-prefs:
  qvm.prefs:
    - name: {{ vm }}
    - memory: {{ memory }}
    - maxmem: {{ maxmem }}
    - vcpus: {{ vcpus }}
    - require:
      - qvm: makemkv-create-appvm

makemkv-appvm-volume:
  cmd.run:
    - name: >
        qvm-volume resize {{ vm }}:private {{ storage }}MiB
    - require:
      - qvm: makemkv-create-appvm

# ---------------------------------------------------------------------------
# 2. Write the build script into dom0 /tmp so we can copy it into the VM
# ---------------------------------------------------------------------------

makemkv-write-build-script:
  file.managed:
    - name: /tmp/makemkv-build.sh
    - mode: '0755'
    - contents: |
        #!/bin/bash
        set -e
        
        HOME_DIR="/home/user"
        OSS_VERSION="1.18.3"
        BIN_VERSION="1.18.3"
        OSS_DIR="makemkv-oss-${OSS_VERSION}"
        BIN_DIR="makemkv-bin-${BIN_VERSION}"
        FFMPEG_ARCHIVE="ffmpeg-release-amd64-static.tar.xz"
        FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/${FFMPEG_ARCHIVE}"
        MAKEMKV_OSS_URL="https://www.makemkv.com/download/${OSS_DIR}.tar.gz"
        MAKEMKV_BIN_URL="https://www.makemkv.com/download/${BIN_DIR}.tar.gz"
        WRAPPER="$HOME_DIR/.local/bin/makemkv"
        
        mkdir -p "$HOME_DIR/.local/bin"
        
        if ! grep -qF '.local/bin' "$HOME_DIR/.bashrc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME_DIR/.bashrc"
        fi
        
        export PATH="$HOME_DIR/.local/bin:$PATH"
        
        cd "$HOME_DIR"
        
        sudo apt-get update
        sudo apt-get install -y build-essential pkg-config libc6-dev libssl-dev \
            libexpat1-dev libavcodec-dev libgl1-mesa-dev qtbase5-dev zlib1g-dev wget
        
        wget -c "$MAKEMKV_OSS_URL"
        wget -c "$MAKEMKV_BIN_URL"
        
        tar -xf "${OSS_DIR}.tar.gz"
        tar -xf "${BIN_DIR}.tar.gz"
        
        cd "$HOME_DIR/${OSS_DIR}"
        ./configure
        make
        sudo make install
        
        cd "$HOME_DIR/${BIN_DIR}"
        mkdir -p tmp
        echo "yes" > tmp/eula_accepted
        make && sudo make install
        
        cd "$HOME_DIR"
        wget -c "$FFMPEG_URL"
        tar -xf "$FFMPEG_ARCHIVE"
        FFMPEG_EXTRACT_DIR=$(find "$HOME_DIR" -maxdepth 1 -type d -name "ffmpeg-*-amd64-static" | head -1)
        
        if [ -z "$FFMPEG_EXTRACT_DIR" ]; then
            echo "ERROR: Could not find extracted ffmpeg directory." >&2
            exit 1
        fi
        
        mv "${FFMPEG_EXTRACT_DIR}/ffprobe" "${FFMPEG_EXTRACT_DIR}/ffmpeg" \
            "$HOME_DIR/.local/bin/"
        
        # Create the makemkv wrapper
        cat > "$WRAPPER" << EOF
        #!/bin/bash
        # Re-install MakeMKV libraries before launching (handles Qubes AppVM resets)
        cd "$HOME_DIR/${OSS_DIR}"
        sudo make install
        
        cd "$HOME_DIR/${BIN_DIR}"
        mkdir -p tmp && echo accepted > tmp/eula_accepted
        sudo make install
        
        # Pass all arguments through to the real makemkv binary
        exec /usr/bin/makemkv "\$@"
        EOF
        
        chmod 0755 "$WRAPPER"
        
        echo "MakeMKV and ffmpeg installation complete."


# ---------------------------------------------------------------------------
# 3. Start the VM, copy the script in, run it, then shut the VM down
# ---------------------------------------------------------------------------

makemkv-start-appvm:
  cmd.run:
    - name: qvm-start --skip-if-running {{ vm }}
    - require:
      - qvm: makemkv-appvm-prefs
      - file: makemkv-write-build-script

makemkv-copy-script:
  cmd.run:
    - name: qvm-copy-to-vm {{ vm }} /tmp/makemkv-build.sh
    - require:
      - cmd: makemkv-start-appvm

makemkv-run-build:
  cmd.run:
    - name: >
        qvm-run --pass-io {{ vm }}
        'bash /home/user/QubesIncoming/dom0/makemkv-build.sh'
    - require:
      - cmd: makemkv-copy-script

# ---------------------------------------------------------------------------
# Write the .desktop file into dom0 /tmp, then copy it into the VM
# ---------------------------------------------------------------------------

makemkv-write-desktop-file:
  file.managed:
    - name: /tmp/makemkv.desktop
    - mode: '0644'
    - contents: |
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=MakeMKV
        Comment=Convert Blu-ray and DVD to MKV
        Exec=/home/user/.local/bin/makemkv
        Icon=makemkv
        Terminal=false
        Categories=AudioVideo;Video;

makemkv-copy-desktop-file:
  cmd.run:
    - name: qvm-copy-to-vm {{ vm }} /tmp/makemkv.desktop

makemkv-create-share-app-dir:
  cmd.run:
    - name: >
        qvm-run --pass-io {{ vm }} 'mkdir -p /home/user/.local/share/applications'

makemkv-install-desktop-file:
  cmd.run:
    - name: >
        qvm-run {{ vm }} 'cp /home/user/QubesIncoming/dom0/makemkv.desktop /home/user/.local/share/applications/makemkv.desktop'

makemkv-shutdown-appvm:
  cmd.run:
    - name: qvm-shutdown --wait {{ vm }}
    - require:
      - cmd: makemkv-run-build

{%- endif %}

