{% set zk_hosts = salt['mine.get']('G@stack_id:' ~ grains.stack_id ~ ' and G@roles:mapr.zookeeper', 'grains.items', 'compound').values() | map(attribute='fqdn') | join(',') %}
{% set cldb_hosts = salt['mine.get']('G@stack_id:' ~ grains.stack_id ~ ' and G@roles:mapr.cldb', 'grains.items', 'compound').values() | map(attribute='fqdn') | join(',') %}
{% set rm_hosts = salt['mine.get']('G@stack_id:' ~ grains.stack_id ~ ' and G@roles:mapr.yarn.resourcemanager', 'grains.items', 'compound').values() | map(attribute='fqdn') | join(',') %}
{% set hs_hosts = salt['mine.get']('G@stack_id:' ~ grains.stack_id ~ ' and G@roles:mapr.mapreduce.historyserver', 'grains.items', 'compound').values() | map(attribute='fqdn') | join(',') %}
{% set kdc_host = salt['mine.get']('G@stack_id:' ~ grains.stack_id ~ ' and G@roles:krb5.kdc', 'grains.items', 'compound').keys()[0] %}

{% if pillar.mapr.kerberos %}
include:
  - krb5

# load admin keytab from the master fileserver
load_admin_keytab:
  module:
    - run
    - name: cp.get_file
    - path: salt://{{ kdc_host }}/root/admin.keytab
    - dest: /root/admin.keytab
    - user: root
    - group: root
    - mode: 600
    - require:
      - file: krb5_conf_file
      - pkg: krb5-workstation
      - pkg: krb5-libs

generate_http_keytab:
  cmd:
    - script
    - source: salt://mapr/generate_mapr_keytab.sh
    - template: jinja
    - user: root
    - group: root
    - unless: test -f /opt/mapr/conf/mapr.keytab
    - require:
      - module: load_admin_keytab
    - require_in:
      - cmd: finalize
{% endif %}

{% set config_command = '/opt/mapr/server/configure.sh -N ' ~ grains.namespace ~ ' -Z ' ~ zk_hosts ~ ' -C ' ~ cldb_hosts ~ ' -RM ' ~ rm_hosts ~ ' -HS ' ~ hs_hosts ~ ' -noDB' %}

{% if pillar.mapr.kerberos %}
  {% set config_command = config_command ~ ' -K' %}
  {% if 'mapr.cldb' in grains.roles %}
    {%- from 'krb5/settings.sls' import krb5 with context -%}
    {% set config_command = config_command ~ ' -P "mapr/' ~ grains.namespace ~ '@' ~ krb5.realm ~ '"' %}
  {% endif %}
{% endif %}

# of the following 2 commands, only 1 should be run.

{% set fixed_roles = ['fileserver', 'cldb', 'webserver'] %}

# Run this if the user does exist
finalize:
  cmd:
    - run
    - user: root
    - name: {{ config_command }}
    - onlyif: id -u mapr{% for role in fixed_roles %}{% if 'mapr.' ~ role in grains.roles %} && test -f /opt/mapr/roles/{{ role }}{% endif %}{% endfor %}

# Run this if the user doesn't exist
try-create-user:
  cmd:
    - run
    - user: root
    - name: {{ config_command }} --create-user
    - unless: id -u mapr
    - onlyif: true{% for role in fixed_roles %}{% if 'mapr.' ~ role in grains.roles %} && test -f /opt/mapr/roles/{{ role }}{% endif %}{% endfor %}
    - require:
      - cmd: finalize

{% if 'mapr.fileserver' in grains.roles %}
/tmp/disks.txt:
  file:
    - managed
    - user: root
    - group: root
    - mode: 644
    - contents:
      {% for disk in pillar.mapr.fs_disks %}
      - {{ disk }}
      {% endfor %}

setup-disks:
  cmd:
    - run
    - user: root
    - name: '/opt/mapr/server/disksetup /tmp/disks.txt'
    - unless: cat /opt/mapr/conf/disktab | grep {{ pillar.mapr.fs_disks[0] }}
    - onlyif: true{% for role in fixed_roles %}{% if 'mapr.' ~ role in grains.roles %} && test -f /opt/mapr/roles/{{ role }}{% endif %}{% endfor %}
    - require:
      - file: /tmp/disks.txt
      - cmd: finalize
      - cmd: try-create-user
{% endif %}
