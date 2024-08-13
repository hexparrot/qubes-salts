# USAGE: sudo qubesctl --target=SRCVM --show-output state.sls portforward saltenv=user

{% set connections = salt['pillar.get']('dmz_networking:connections') %}
{% set ports_to_keep = connections | map(attribute='port') | join(' ') %}

{% if grains['id'] == 'dom0' %}

dmz_cleanup_old_policy_files:
  cmd.run:
    - name: |
        for policy in /etc/qubes/policy.d/30-dmz-networking*; do
          port=$(basename "$policy" | cut -d'-' -f4 | cut -d"." -f1)
          if ! echo "{{ ports_to_keep }}" | grep -wq "$port"; then
            rm -f "$policy"
          fi
        done
    - onlyif: test -n "$(ls /etc/qubes/policy.d/30-dmz-networking* 2>/dev/null)"

{% endif %}

{% if not connections %}

check_if_no_connections_enumerated:
  test.succeed_without_changes:
    - name: "user_pillar data for dmz_networking:connections is absent; skipping portforwarding"

{% else %}

  {% set port = salt['pillar.get']('dmz_networking:port') %}
  {% set source_vm = salt['pillar.get']('dmz_networking:source_vm') %}
  {% set target_vm = salt['pillar.get']('dmz_networking:target_vm') %}

  {% for connection in connections %}

    {% if grains['id'] == 'dom0' %}

/etc/qubes/policy.d/30-dmz-networking-{{ connection['port'] }}.policy:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - require:
      - cmd: dmz_cleanup_old_policy_files
    - contents: |
        qubes.ConnectTCP +{{ connection['port'] }} {{ connection['source_vm'] }} @default allow target={{ connection['target_vm'] }}

    {% elif grains['id'] == connection['source_vm'] %}

dmz_tcp_forward_{{ connection['port'] }}:
  cmd.run:
    - name: qvm-connect-tcp {{ connection['port'] }}:@default:{{ connection['port'] }}
    - unless: ss -tuln | grep -q ':{{ connection['port'] }} '

dmz_nft_rule_{{ connection['port'] }}:
  cmd.run:
    - name: nft add rule ip qubes input tcp dport {{ connection['port'] }} accept
    - unless: nft list ruleset | grep -q 'tcp dport {{ connection['port'] }} accept'

    {% endif %}

  {% endfor %}

{% endif %}
