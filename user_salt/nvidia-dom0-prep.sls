{%- set nvidia = salt['pillar.get']('nvidia', {}) %}
{%- set driver_path = nvidia.get('driver_dom0_path', '') %}
{%- set driver_file = nvidia.get('driver_filename', 'nvidia.run') %}
{%- set templates = nvidia.get('templates', []) %}

{%- if grains['id'] != 'dom0' %}

nvidia-dom0-only:
  test.fail_without_changes:
    - name: "nvidia-dom0-prep must only run on dom0"

{%- elif not driver_path %}

nvidia-pillar-driver-path-missing:
  test.fail_without_changes:
    - name: "nvidia:driver_dom0_path is not set in pillar"

{%- elif not templates %}

nvidia-pillar-templates-missing:
  test.fail_without_changes:
    - name: "nvidia:templates list is empty in pillar"

{%- else %}

{%- for tpl in templates %}
{%- set vm = tpl.get('name', '') %}
{%- set incoming = '/home/user/QubesIncoming/dom0/' ~ driver_file %}
{%- set nvidia_src = '/home/user/nvidia' %}

{%- if not vm %}

nvidia-template-name-missing-{{ loop.index }}:
  test.fail_without_changes:
    - name: "nvidia:templates entry {{ loop.index }} is missing its name field"

{%- elif not tpl.get('source_template', '') %}

nvidia-source-template-missing-{{ vm }}:
  test.fail_without_changes:
    - name: "nvidia:templates entry {{ vm }} is missing source_template"

{%- else %}

{{ vm }}--create-vm:
  qvm.vm:
    - name: {{ vm }}
    - present:
      - class: StandaloneVM
      - label: {{ tpl.get('label', 'orange') }}
      - template: {{ tpl['source_template'] }}
    - prefs:
      - include-in-backups: False
      - kernel: ''
      - kernelopts: ''
      - memory: {{ tpl.get('memory', 2096) }}
      - maxmem: {{ tpl.get('maxmem', 4092) }}
      - vcpus: {{ tpl.get('vcpus', 4) }}
      - virt-mode: hvm
    - features:
      - enable:
        - no-default-kernelopts

{{ vm }}--resize-private-volume:
  cmd.run:
    - name: qvm-volume resize {{ vm }}:private {{ tpl.get('private_storage', '20GiB') }}
    - require:
      - qvm: {{ vm }}--create-vm

{{ vm }}--copy-nvidia-driver:
  cmd.run:
    - name: qvm-copy-to-vm {{ vm }} {{ driver_path }}
    - unless: qvm-run --no-gui {{ vm }} 'test -f {{ incoming }}'
    - require:
      - qvm: {{ vm }}--create-vm

{{ vm }}--apt-update:
  cmd.run:
    - name: qvm-run -u root --no-gui {{ vm }} "apt-get update -q"
    - require:
      - cmd: {{ vm }}--copy-nvidia-driver

{{ vm }}--apt-install-deps:
  cmd.run:
    - name: >
        qvm-run -u root --no-gui {{ vm }}
        "apt-get install -y make gcc dracut linux-headers-amd64"
    - unless: >
        qvm-run --no-gui {{ vm }}
        "dpkg -l make gcc dracut linux-headers-amd64 2>/dev/null | grep -c '^ii' | grep -qx '4'"
    - require:
      - cmd: {{ vm }}--apt-update

{{ vm }}--chmod-driver:
  cmd.run:
    - name: qvm-run --no-gui {{ vm }} "chmod +x {{ incoming }}"
    - unless: qvm-run --no-gui {{ vm }} "test -d {{ nvidia_src }}"
    - require:
      - cmd: {{ vm }}--apt-install-deps

{{ vm }}--extract-driver:
  cmd.run:
    - name: >
        qvm-run -u user --no-gui {{ vm }}
        "{{ incoming }} --no-x-check --ui=none --keep --extract-only"
    - unless: qvm-run --no-gui {{ vm }} "test -d {{ nvidia_src }}"
    - require:
      - cmd: {{ vm }}--chmod-driver

{{ vm }}--rename-driver-src:
  cmd.run:
    - name: >
        qvm-run -u user --no-gui {{ vm }}
        "mv /home/user/NVIDIA* {{ nvidia_src }}"
    - unless: qvm-run --no-gui {{ vm }} "test -d {{ nvidia_src }}"
    - require:
      - cmd: {{ vm }}--extract-driver

{{ vm }}--shutdown-for-device-assignment:
  qvm.shutdown:
    - name: {{ vm }}
    - flags:
      - quiet
      - wait
    - require:
      - cmd: {{ vm }}--rename-driver-src

{%- endif %}
{%- endfor %}

{%- endif %}


