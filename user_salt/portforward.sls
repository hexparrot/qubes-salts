# USAGE: sudo qubesctl --targets=SRCVM,SRCVM --show-output state.sls portforward saltenv=user

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

  {% set grouped_connections = {} %}
  {% for connection in connections %}
    {% set port = connection['port'] %}
    {% if port in grouped_connections %}
      {% set _ = grouped_connections[port].append(connection) %}
    {% else %}
      {% set _ = grouped_connections.update({port: [connection]}) %}
    {% endif %}
  {% endfor %}

  {% for port, conn_group in grouped_connections.items() %}

    {% if grains['id'] == 'dom0' %}

/etc/qubes/policy.d/30-dmz-networking-{{ port }}.policy:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - require:
      - cmd: dmz_cleanup_old_policy_files
    - contents: |
        {% for connection in conn_group %}
        qubes.ConnectTCP +{{ port }} {{ connection['source_vm'] }} @default allow target={{ connection['target_vm'] }}
        {% endfor %}

    {% endif %}

    {% for connection in conn_group %}
      {% if grains['id'] == connection['source_vm'] %}

dmz_tcp_forward_{{ port }}_{{ connection['source_vm'] }}:
  cmd.run:
    - name: qvm-connect-tcp {{ port }}:@default:{{ port }}
    - unless: ss -tuln | grep -q ':{{ port }} '

dmz_nft_rule_{{ port }}_{{ connection['source_vm'] }}:
  cmd.run:
    - name: nft add rule ip qubes input tcp dport {{ port }} accept
    - unless: nft list ruleset | grep -q 'tcp dport {{ port }} accept'

      {% endif %}
    {% endfor %}

  {% endfor %}

{% endif %}
