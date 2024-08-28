# sudo qubesctl --skip-dom0 --targets=disp1509,whisper-server state.sls whisper-gpu saltenv=user
# this is for faster-whisper-server GPU on debian
# in audio source domU: ffmpeg -f pulse -i qubes-sink.monitor -acodec pcm_s16le -f wav - | socat -u - TCP:localhost:8001
# it may be necessary to manually kick services: `systemctl restart stream_receiver`
# in whisper-server-gpu, `tail -f /home/user/sr.log` for transcriptions

{% if grains['id'] == 'dom0' %}

whisper-server-gpu--create-qubes:
  qvm.vm:
    - name: {{ salt['pillar.get']('whisper_server_gpu:name') }}
    - present:
      - class: {{ salt['pillar.get']('whisper_server_gpu:class') }}
      - template: {{ salt['pillar.get']('whisper_server_gpu:template') }}
      - label: {{ salt['pillar.get']('whisper_server_gpu:label') }}
    - prefs:
      - label: {{ salt['pillar.get']('whisper_server_gpu:label') }}
      - memory: {{ salt['pillar.get']('whisper_server_gpu:memory') }}
      - maxmem: {{ salt['pillar.get']('whisper_server_gpu:maxmem') }}
      - vcpus: {{ salt['pillar.get']('whisper_server_gpu:vcpus') }}

whisper-server-gpu--startup:
  qvm.start:
    - name: {{ salt['pillar.get']('whisper_server_gpu:name') }}

whisper-server-gpu--dom0-policy-update:
  file.managed:
    - name: /etc/qubes/policy.d/30-dmz-networking-{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }}.policy
    - user: root
    - group: root
    - mode: 644
    - contents: |
        qubes.ConnectTCP +{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }} {{ salt['pillar.get']('whisper_server_gpu:audiosrc') }} @default allow target={{ salt['pillar.get']('whisper_server_gpu:name') }}

{% elif grains['id'] == salt['pillar.get']('whisper_server_gpu:name') %}

whisper-server-gpu--install-deps:
  pkg.installed:
    - pkgs:
      - ffmpeg
      - socat
      - python3-pip
      - ca-certificates
      - curl

whisper-server-gpu--create_keyrings_directory:
  file.directory:
    - name: /etc/apt/keyrings
    - mode: 0755

whisper-server-gpu--fetch_docker_gpg_key:
  cmd.run:
    - name: curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    - creates: /etc/apt/keyrings/docker.asc
    - unless: test -f /etc/apt/keyrings/docker.asc

whisper-server-gpu--set_gpg_key_permissions:
  file.managed:
    - name: /etc/apt/keyrings/docker.asc
    - mode: 0644

whisper-server-gpu--add_docker_repo:
  file.managed:
    - name: /etc/apt/sources.list.d/docker.list
    - contents: |
        deb [arch={{ grains['osarch'] }} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian {{ grains['oscodename'] }} stable
    - mode: 0644

whisper-server-gpu--apt_update:
  cmd.run:
    - name: apt-get update
    - refresh: true

{% set distro = 'debian12' %}  # Set the appropriate distribution
{% set arch = 'x86_64' %}

whisper-server-gpu--download_cuda_keyring_package:
  cmd.run:
    - name: wget https://developer.download.nvidia.com/compute/cuda/repos/{{ distro }}/{{ arch }}/cuda-keyring_1.1-1_all.deb
    - cwd: /tmp
    - creates: /tmp/cuda-keyring_1.1-1_all.deb

whisper-server-gpu--install_cuda_keyring_package:
  cmd.run:
    - name: dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
    - unless: dpkg -l | grep -q cuda-keyring

whisper-server-gpu--move_cuda_archive_keyring:
  cmd.run:
    - name: mv /tmp/cuda-archive-keyring.gpg /usr/share/keyrings/cuda-archive-keyring.gpg
    - unless: test -f /usr/share/keyrings/cuda-archive-keyring.gpg

whisper-server-gpu--add_cuda_repository:
  file.managed:
    - name: /etc/apt/sources.list.d/cuda-{{ distro }}-x86_64.list
    - contents: |
        deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/{{ distro }}/x86_64/ /
    - mode: 0644

whisper-server-gpu--apt_update_again:
  cmd.run:
    - name: apt-get update
    - refresh: true

whisper-server-gpu--install-cudnn:
  pkg.installed:
    - pkgs:
      - cudnn9-cuda-12
      - nvidia-container-toolkit

whisper-server-gpu--install-docker:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli

whisper-server-gpu--docker-startup:
  service.running:
    - name: docker
    - enable: True

whisper-server-gpu--ensure-cache:
  file.directory:
    - name: /home/user/.cache
    - user: user
    - group: user
    - mode: 755

whisper-server-gpu--ensure-huggingface-cache:
  file.directory:
    - name: /home/user/.cache/huggingface
    - user: user
    - group: user
    - mode: 755

whisper-server-gpu--docker-pip:
  pip.installed:
    - name: docker
    - env:
      - PIP_BREAK_SYSTEM_PACKAGES: "1"
    - require:
      - pkg: whisper-server-gpu--install-docker

whisper-server-gpu--container-run:
  cmd.run:
    - name: docker run -d --gpus=all --publish 8000:8000 --volume ~/.cache/huggingface:/root/.cache/huggingface --restart unless-stopped fedirz/faster-whisper-server:latest-cuda
    - unless: >
        docker ps --filter "name=faster-whisper-server" --format "{% raw %}{{.Names}}{% endraw %}" | grep -w faster-whisper-server

whisper-server-gpu--copy-stream-receiver:
  file.managed:
    - name: /home/user/stream_receiver
    - source: salt://copy_usr_bin/stream_receiver
    - user: user
    - group: user
    - mode: 755
    - dir_mode: 755

whisper-server-gpu--stream_receiver_service:
  file.managed:
    - name: /etc/systemd/system/stream_receiver.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=Audio Stream Receiver
        After=network.target

        [Service]
        ExecStart=/usr/bin/python3 /home/user/stream_receiver
        WorkingDirectory=/home/user
        Restart=always
        User=user
        Group=user
        Environment=PYTHONUNBUFFERED=1
        StandardOutput=append:/home/user/sr.log

        [Install]
        WantedBy=multi-user.target

whisper-server-gpu--enable_stream_receiver_service:
  service.running:
    - name: stream_receiver
    - enable: True
    - watch:
      - file: whisper-server-gpu--stream_receiver_service

{% elif grains['id'] == salt['pillar.get']('whisper_server_gpu:audiosrc') %}

whisper-server-gpu--tcp_forward_{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }}:
  cmd.run:
    - name: qvm-connect-tcp {{ salt['pillar.get']('whisper_server_gpu:audiodestport') }}:@default:{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }}
    - unless: ss -tuln | grep -q ':{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }} '

whisper-server-gpu--nft_rule_{{ salt['pillar.get']('whisper_server_gpu:audiodestport') }}:
  cmd.run:
    - name: nft add rule ip qubes input tcp dport {{ salt['pillar.get']('whisper_server_gpu:audiodestport') }} accept
    - unless: nft list ruleset | grep -q "tcp dport {{ salt['pillar.get']('whisper_server_gpu:audiodestport') }} accept"

{% endif %}
