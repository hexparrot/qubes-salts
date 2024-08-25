#sudo qubesctl --skip-dom0 --targets=<TEMPLATEVM> state.apply usr-bin-copy saltenv=user

copy_usr_bin_files:
  file.recurse:
    - name: /usr/bin/
    - source: salt://copy_usr_bin/
    - user: root
    - group: root
    - file_mode: 755
    - dir_mode: 755
    - saltenv: user
