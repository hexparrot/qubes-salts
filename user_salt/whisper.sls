# sudo qubesctl --skip-dom0 --targets=personal,whisper-server state.sls whisper saltenv=user
# this is for faster-whisper-server CPU on fedora; GPU does work on debian, but requires a more involving salt recipe
# in audio source domU: ffmpeg -f pulse -i qubes-sink.monitor -acodec pcm_s16le -f wav - | socat -u - TCP:localhost:8001
# it may be necessary to manually kick services: `systemctl restart stream_receiver`
# in whisper-server, `tail -f /home/user/sr.log` for transcriptions

{% if grains['id'] == 'dom0' %}

whisper-server--create-qubes:
  qvm.vm:
    - name: {{ salt['pillar.get']('whisper_server:name') }}
    - present:
      - class: {{ salt['pillar.get']('whisper_server:class') }}
      - template: {{ salt['pillar.get']('whisper_server:template') }}
      - label: {{ salt['pillar.get']('whisper_server:label') }}
    - prefs:
      - label: {{ salt['pillar.get']('whisper_server:label') }}
      - memory: {{ salt['pillar.get']('whisper_server:memory') }}
      - maxmem: {{ salt['pillar.get']('whisper_server:maxmem') }}
      - vcpus: {{ salt['pillar.get']('whisper_server:vcpus') }}

whisper-server--startup:
  qvm.start:
    - name: {{ salt['pillar.get']('whisper_server:name') }}

whisper-server--dom0-policy-update:
  file.managed:
    - name: /etc/qubes/policy.d/30-dmz-networking-{{ salt['pillar.get']('whisper_server:audiodestport') }}.policy
    - user: root
    - group: root
    - mode: 644
    - contents: |
        qubes.ConnectTCP +{{ salt['pillar.get']('whisper_server:audiodestport') }} {{ salt['pillar.get']('whisper_server:audiosrc') }} @default allow target={{ salt['pillar.get']('whisper_server:name') }}


{% elif grains['id'] == salt['pillar.get']('whisper_server:name') %}

whisper-server--install-deps:
  pkg.installed:
    - pkgs:
      - ffmpeg-free
      - dnf-plugins-core
      - socat
      - python3-pip

whisper-server--install-docker-repo:
  cmd.run:
    - name: sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    - unless: test -f /etc/yum.repos.d/docker-ce.repo

whisper-server--install-docker:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli

whisper-server--docker-startup:
  service.running:
    - name: docker
    - enable: True

whisper-server--ensure-cache:
  file.directory:
    - name: /home/user/.cache
    - user: user
    - group: user
    - mode: 755

whisper-server--ensure-huggingface-cache:
  file.directory:
    - name: /home/user/.cache/huggingface
    - user: user
    - group: user
    - mode: 755

whisper-server--docker-pip:
  pip.installed:
    - name: docker
    - require:
      - pkg: whisper-server--install-docker

whisper-server--whisper-download:
  docker_container.running:
    - name: faster-whisper-server
    - image: fedirz/faster-whisper-server:latest-cpu
    - port_bindings:
      - "8000:8000"
    - binds:
      - "/home/user/.cache/huggingface:/root/.cache/huggingface"
    - restart_policy: unless-stopped
    - detach: True
    - require:
      - file: whisper-server--ensure-huggingface-cache

whisper-server--copy-stream-receiver:
  file.managed:
    - name: /home/user/stream_receiver
    - source: salt://copy_usr_bin/stream_receiver
    - user: user
    - group: user
    - file_mode: 755
    - dir_mode: 755

whisper-server--stream_receiver_service:
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

whisper-server--enable_stream_receiver_service:
  service.running:
    - name: stream_receiver
    - enable: True
    - watch:
      - file: whisper-server--stream_receiver_service

{% elif grains['id'] == salt['pillar.get']('whisper_server:audiosrc') %}

whisper-server--tcp_forward_{{ salt['pillar.get']('whisper_server:audiodestport') }}:
  cmd.run:
    - name: qvm-connect-tcp {{ salt['pillar.get']('whisper_server:audiodestport') }}:@default:{{ salt['pillar.get']('whisper_server:audiodestport') }}
    - unless: ss -tuln | grep -q ':{{ salt['pillar.get']('whisper_server:audiodestport') }} '

whisper-server--nft_rule_{{ salt['pillar.get']('whisper_server:audiodestport') }}:
  cmd.run:
    - name: nft add rule ip qubes input tcp dport {{ salt['pillar.get']('whisper_server:audiodestport') }} accept
    - unless: nft list ruleset | grep -q "tcp dport {{ salt['pillar.get']('whisper_server:audiodestport') }} accept"

{% endif %}

