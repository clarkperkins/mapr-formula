
include:
  - mapr.repo
  - mapr.hadoop-conf
  - mapr.final

mapr-nodemanager:
  pkg:
    - installed
    - require:
      - cmd: mapr-key
    - require_in:
      - file: hadoop-conf
      - file: /opt/mapr/conf/env.sh

/opt/tmp:
  file:
    - directory
    - user: root
    - group: root
    - mode: 777

extend:
  finalize:
    cmd:
      - require:
        - file: hadoop-conf
        - file: /opt/tmp
  yarn-site:
    file:
      - require:
        - cmd: try-create-user

nm-login:
  cmd:
    - run
    - name: echo '1234' | maprlogin password
    - user: mapr
    - require:
      - cmd: add-password

# Give the RM time to spin up
nm-wait:
  cmd:
    - run
    - name: sleep 30
    - require:
      - cmd: nm-login

restart-nodemanager:
  cmd:
    - run
    - name: 'maprcli node services -name nodemanager -action restart -nodes {{ grains.fqdn }}'
    - user: mapr
    - require:
      - file: yarn-site
      - cmd: nm-login
      - cmd: nm-wait

nm-logout:
  cmd:
    - run
    - name: maprlogin logout
    - user: mapr
    - require:
      - cmd: nm-login
      - cmd: restart-nodemanager
