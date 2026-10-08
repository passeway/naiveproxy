import base64
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import subprocess
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'naive.sh'
CORE = os.environ.get('CADDY_TEST_BINARY', '')

class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = f'''source {shlex.quote(str(SCRIPT))}
BINARY={shlex.quote(str(self.root/'bin/caddy'))}
CONFIG_DIR={shlex.quote(str(self.root/'etc'))}
CONFIG_FILE="$CONFIG_DIR/Caddyfile"; CLIENT_FILE="$CONFIG_DIR/config.txt"; META_FILE="$CONFIG_DIR/naive-manager.json"
DATA_DIR={shlex.quote(str(self.root/'data'))}
CRON_FILE={shlex.quote(str(self.root/'cron/rotate'))}
ROTATE_STATE={shlex.quote(str(self.root/'rotate.state'))}
LOCK_FILE={shlex.quote(str(self.root/'lock'))}
service_file() {{ echo {shlex.quote(str(self.root/'service'))}; }}
'''
    def shell(self, code, data='', status=0, timeout=15):
        r = subprocess.run(['bash', '-c', self.prefix+code], input=data, text=True, capture_output=True, timeout=timeout)
        self.assertEqual(r.returncode, status, r.stdout+r.stderr)
        return r
    def test_architecture_mapping_and_rejection(self):
        for arch, expected in [('x86_64','amd64'),('aarch64','arm64'),('arm64','arm64')]:
            self.assertEqual(self.shell(f'uname() {{ echo {arch}; }}; get_architecture').stdout.strip(), expected)
        self.shell('uname() { echo armv7l; }; get_architecture', status=1)
    def test_dependency_failure_stops_operation(self):
        for system,cmd in [('alpine','apk'),('debian','apt-get')]:
            code=f'get_system_type() {{ echo {system}; }}; {cmd}() {{ return 17; }}; check_ports() {{ echo BAD; }}; install_or_update install'
            self.assertNotIn('BAD', self.shell(code,status=1).stdout)
    def test_no_system_upgrade_and_correct_alpine_cron_dependency(self):
        out=self.shell('get_system_type() { echo alpine; }; apk() { printf "%s\\n" "$*"; }; install_dependencies').stdout
        self.assertIn('busybox-openrc',out)
        self.assertNotIn('busybox-initscripts',out)
        out=self.shell('get_system_type() { echo debian; }; apt-get() { printf "%s\\n" "$*"; }; install_dependencies').stdout
        self.assertNotIn('upgrade',out)
    def test_conflicting_ports_are_not_killed(self):
        for port in (80,443):
            out=self.shell(f'ss() {{ echo "LISTEN 0 128 *:{port} *:*"; }}; kill() {{ echo BAD; }}; check_ports',status=1)
            self.assertNotIn('BAD',out.stdout)
        self.shell('ss() { echo "LISTEN 0 128 *:1443 *:*"; }; check_ports')
    def test_domain_and_email_reject_injection(self):
        for host in ('', '127.0.0.1', 'x\nrespond hacked', 'example.com:443', 'a;id.example'):
            self.shell('data_tool domain '+shlex.quote(host),status=1)
        self.assertEqual(self.shell('data_tool domain Proxy.Example.COM.').stdout.strip(),'proxy.example.com')
        self.shell(f'data_tool new {shlex.quote(str(self.root))} proxy.example.com "bad mail" /site',status=1)
    def test_dns_address_family_match_and_cancel(self):
        common='timeout() { printf "2001:db8::1\\n203.0.113.8\\n"; }; '
        self.shell(common+'fetch_public_ip() { echo 203.0.113.8; }; check_domain_dns proxy.example.com')
        self.shell(common+'fetch_public_ip() { return 1; }; check_domain_dns proxy.example.com',data='n\n',status=1)
        self.shell(common+'fetch_public_ip() { return 1; }; check_domain_dns proxy.example.com',data='y\n')
    def test_atomic_write_survives_errors(self):
        dest=self.root/'secret';dest.write_text('old')
        for command in ('cat','chown','chmod','mv'):
            self.shell(f'{command}() {{ return 1; }}; write_file {shlex.quote(str(dest))} 600 root:root <<< new',status=1)
            self.assertEqual(dest.read_text(),'old')
            self.assertFalse(list(self.root.glob('secret.tmp.*')))
    def test_lock_released_between_actions(self):
        self.shell('with_lock true; with_lock true')
        out=self.shell('with_lock with_lock true',status=1)
        self.assertIn('已有',out.stderr)
    def test_daemon_does_not_inherit_lock_descriptor(self):
        probe=self.root/'probe';probe.write_text('#!/bin/sh\nif [ -e /proc/self/fd/9 ]; then exit 19; fi\n');probe.chmod(0o755)
        for system,cmd in [('alpine','rc-service'),('debian','systemctl')]:
            self.shell(f'get_system_type() {{ echo {system}; }}; {cmd}() {{ {shlex.quote(str(probe))}; }}; with_lock service_action start')
    def test_eof_and_menu_numbers(self):
        common='id() { echo 0; }; get_system_type() { echo alpine; }; get_architecture() { :; }; ensure_lock_tool() { :; }; is_running() { return 1; }; main'
        for data in ('','invalid\n'):
            out=self.shell(common,data=data).stdout
            self.assertEqual(out.count('=== NaïveProxy 管理工具 ==='),1)
        out=self.shell('is_installed() { return 0; }; is_running() { return 1; }; show_menu',data='0\n').stdout
        lines=[x.split('.')[0] for x in out.splitlines() if x[:1].isdigit()]
        self.assertEqual(lines,['1','2','3','4','5','6','7','8','9','0'])
    def test_uninstall_requires_yes_and_managed_installation(self):
        for data in ('','\n','n\n'):
            r=self.shell('require_managed() { :; }; service_action() { echo BAD; }; uninstall_service',data=data)
            self.assertNotIn('BAD',r.stdout)
        self.shell('uninstall_service',data='y\n',status=1)
    def test_validate_before_start_or_restart(self):
        r=self.shell('require_managed() { :; }; validate_config() { return 1; }; service_action() { echo BAD; }; start_or_restart restart',status=1)
        self.assertNotIn('BAD',r.stdout)
    def test_release_selection_and_digest_required(self):
        digest='a'*64
        release={'draft':False,'prerelease':False,'tag_name':'v2.11.4','assets':[
            {'name':'caddy_2.11.4_linux_arm64.tar.gz','browser_download_url':'https://github.com/passeway/naiveproxy/releases/download/v2.11.4/caddy_2.11.4_linux_arm64.tar.gz','digest':'sha256:'+digest}]}
        p=self.root/'release.json';p.write_text(json.dumps(release))
        out=self.shell(f'data_tool release {p} arm64').stdout
        self.assertIn('\t'+digest,out)
        self.shell(f'data_tool release {p} amd64',status=1)
        release['assets'][0]['browser_download_url']='https://example.com/caddy.tar.gz';p.write_text(json.dumps(release))
        self.shell(f'data_tool release {p} arm64',status=1)
    def test_archive_integrity_and_symlink_rejection(self):
        p=self.root/'archive.tar.gz';target=self.root/'caddy'
        with tarfile.open(p,'w:gz') as tar:
            member=tarfile.TarInfo('caddy');member.size=5;tar.addfile(member,io.BytesIO(b'hello'))
        digest=hashlib.sha256(p.read_bytes()).hexdigest()
        self.shell(f'data_tool extract {p} {digest} {target}')
        self.assertEqual(target.read_bytes(),b'hello')
        self.shell(f'data_tool extract {p} {"0"*64} {target}',status=1)
        with tarfile.open(p,'w:gz') as tar:
            member=tarfile.TarInfo('caddy');member.type=tarfile.SYMTYPE;member.linkname='/etc/passwd';tar.addfile(member)
        digest=hashlib.sha256(p.read_bytes()).hexdigest()
        self.shell(f'data_tool extract {p} {digest} {target}',status=1)
    def test_export_reads_current_credentials_and_escapes_uri(self):
        creds=base64.b64encode(base64.b64encode('name:p@ss:/?'.encode())).decode()
        config={'apps':{'http':{'servers':{'srv0':{'listen':[':4443'],'routes':[{'handle':[{'handler':'forward_proxy','auth_credentials':[creds]}]}]}}},'tls':{'certificates':{'automate':['proxy.example.com']}}}}
        p=self.root/'adapted.json';p.write_text(json.dumps(config));out=self.root/'clients'
        self.shell(f'data_tool export {p} {self.root}/missing {self.root}/missing HK {out}')
        self.assertIn('p%40ss%3A%2F%3F@proxy.example.com:4443',out.read_text())
        config['apps']['http']['servers']['srv0']['listen']=[':5555'];p.write_text(json.dumps(config))
        self.shell(f'data_tool export {p} {self.root}/missing {out} US {out}')
        self.assertIn(':5555#HK',out.read_text())
        self.assertEqual(out.stat().st_mode&0o777,0o600)
        config['apps']['http']['servers']['srv0']['listen']=[':443'];p.write_text(json.dumps(config))
        self.shell(f'data_tool export {p} {self.root}/missing {out} US {out}')
        link,client=out.read_text().split('\n\n')
        self.assertEqual(link,'naive+https://name:p%40ss%3A%2F%3F@proxy.example.com#HK')
        self.assertEqual(json.loads(client)['proxy'],'https://name:p%40ss%3A%2F%3F@proxy.example.com')
    def test_site_staging_downloads_missing_page_and_preserves_custom_page(self):
        site=self.root/'data/naive-site';site.mkdir(parents=True)
        adapted=self.root/'adapted.json'
        adapted.write_text(json.dumps({'handler':'file_server','root':str(site)}))
        staged=self.root/'index.html';index=site/'index.html'
        fetch=f'curl() {{ cp {shlex.quote(str(ROOT/"index.html"))} "${{@: -1}}"; }}; '
        self.shell(fetch+f'stage_site {self.root}')
        self.assertEqual(staged.read_bytes(),(ROOT/'index.html').read_bytes());staged.unlink()
        index.write_text('my custom homepage')
        self.shell('curl() { echo BAD; return 1; }; '+f'stage_site {self.root}')
        self.assertFalse(staged.exists());self.assertEqual(index.read_text(),'my custom homepage')
        index.unlink();index.symlink_to(ROOT/'index.html')
        self.shell(fetch+f'stage_site {self.root}',status=1)
    def test_site_placeholder_migration_and_nonstatic_configuration(self):
        site=self.root/'data/naive-site';site.mkdir(parents=True)
        index=site/'index.html'
        index.write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Welcome</title><body><h1>Welcome</h1><p>This website is available over HTTPS.</p></body></html>\n')
        adapted=self.root/'adapted.json'
        adapted.write_text(json.dumps({'handler':'file_server','root':str(site)}))
        self.assertEqual(self.shell(f'data_tool site-needed {adapted} {site}').stdout.strip(),'yes')
        adapted.write_text('{"handler":"reverse_proxy"}')
        self.shell('curl() { echo BAD; return 1; }; '+f'stage_site {self.root}')
        self.assertFalse((self.root/'index.html').exists())
    def test_site_check_rejects_truncated_or_error_responses(self):
        page=self.root/'bad.html'
        for value in ('','404: Not Found','<html><head><title>Error</title></head><body>Bad gateway</body></html>', '<html><head><title>T</title></head><body><main>truncated', 'x'*524289):
            page.write_text(value)
            self.shell(f'data_tool site-check {page}',status=1)
        self.shell(f'data_tool site-check {shlex.quote(str(ROOT/"index.html"))}')
    def transaction_stubs(self):
        (self.root/'bin').mkdir();(self.root/'etc').mkdir();(self.root/'data/naive-site').mkdir(parents=True);(self.root/'cron').mkdir()
        for path in ('bin/caddy','etc/Caddyfile','etc/config.txt','service'):
            (self.root/path).write_text('old-'+path)
        (self.root/'bin/caddy').chmod(0o755)
        return '''
require_managed() { :; }; get_architecture() { echo amd64; }; install_dependencies() { :; }
get_system_type() { echo debian; }; prepare_account() { :; }; binary_capability() { :; }
is_running() { return 0; }; is_enabled() { return 0; }; validate_config() { :; }
chown() { :; }; configure_rotation() { :; }; reload_manager() { :; }; enable_service() { :; }; wait_running() { :; }
download_core() { printf '#!/bin/sh\nexit 0\n' > "$1/caddy"; chmod 755 "$1/caddy"; }
export_stage() { echo new-client > "$3/clients"; echo '{}' > "$3/clients.meta"; echo '{}' > "$3/adapted.json"; }
'''
    def test_failed_update_restores_binary_config_and_running_state(self):
        setup=self.transaction_stubs()
        (self.root/'data/naive-site/index.html').write_text('old-site')
        setup+='stage_site() { echo new-site > "$1/index.html"; }; '
        setup+='service_action() { echo "$1" >> "$DATA_DIR/calls"; [ "$1" != restart ]; }; install_or_update update'
        self.shell(setup,status=1)
        for path in ('bin/caddy','etc/Caddyfile','etc/config.txt','service'):
            self.assertEqual((self.root/path).read_text(),'old-'+path)
        self.assertFalse((self.root/'etc/naive-manager.json').exists())
        self.assertEqual((self.root/'data/naive-site/index.html').read_text(),'old-site')
        self.assertEqual((self.root/'data/calls').read_text().splitlines(),['restart','stop','start'])
        self.assertFalse(list((self.root/'bin').glob('.naive-install.*')))
    def test_download_failure_does_not_stop_running_service(self):
        setup=self.transaction_stubs()
        r=self.shell(setup+'download_core() { return 1; }; service_action() { echo BAD; }; install_or_update update',status=1)
        self.assertNotIn('BAD',r.stdout)
        self.assertEqual((self.root/'bin/caddy').read_text(),'old-bin/caddy')
    def test_site_download_failure_does_not_stop_running_service(self):
        setup=self.transaction_stubs()
        r=self.shell(setup+'stage_site() { return 1; }; service_action() { echo BAD; }; install_or_update update',status=1)
        self.assertNotIn('BAD',r.stdout)
        self.assertEqual((self.root/'bin/caddy').read_text(),'old-bin/caddy')
    def test_update_preserves_stopped_and_disabled_state(self):
        setup=self.transaction_stubs()
        r=self.shell(setup+'is_running() { return 1; }; is_enabled() { return 1; }; enable_service() { echo BAD; }; service_action() { echo BAD; }; install_or_update update')
        self.assertNotIn('BAD',r.stdout)
        self.assertEqual((self.root/'etc/Caddyfile').read_text(),'old-etc/Caddyfile')
    def test_failed_first_install_removes_partial_files(self):
        (self.root/'bin').mkdir();(self.root/'etc').mkdir();(self.root/'data/naive-site').mkdir(parents=True);(self.root/'cron').mkdir()
        setup='''get_architecture() { echo amd64; }; get_system_type() { echo debian; }
install_dependencies() { :; }; check_ports() { :; }; check_domain_dns() { :; }; prepare_account() { :; }
chown() { :; }; binary_capability() { :; }; validate_config() { :; }
is_running() { return 1; }; is_enabled() { return 1; }; enable_service() { :; }; reload_manager() { :; }; configure_rotation() { :; }
download_core() { printf '#!/bin/sh\\nexit 0\\n' > "$1/caddy"; chmod 755 "$1/caddy"; }
export_stage() { echo new-client > "$3/clients"; echo '{}' > "$3/clients.meta"; }
stage_site() { echo new-site > "$1/index.html"; }
service_action() { [ "$1" != restart ]; }
install_or_update install'''
        self.shell(setup,data='proxy.example.com\n\n',status=1)
        for path in ('bin/caddy','etc/Caddyfile','etc/config.txt','etc/naive-manager.json','service','data/naive-site/index.html'):
            self.assertFalse((self.root/path).exists(),path)
        self.assertFalse(list((self.root/'bin').glob('.naive-install.*')))
    def test_service_templates_parse_and_drop_root(self):
        for system in ('alpine','debian'):
            text=self.shell(f'get_system_type() {{ echo {system}; }}; service_template').stdout
            if system=='alpine':
                subprocess.run(['sh','-n'],input=text,text=True,check=True)
                self.assertIn('command_user="caddy:caddy"',text)
                self.assertIn('supervise-daemon',text)
            else:self.assertIn('User=caddy',text)
    def test_ctrl_c_log_returns_to_menu(self):
        fake=self.root/'journalctl';fake.write_text('#!/bin/sh\necho LOG_READY\nexec sleep 30\n');fake.chmod(0o755)
        runner=self.root/'runner.sh';runner.write_text(self.prefix+f'export PATH={self.root}:$PATH\nget_system_type() {{ echo debian; }}; show_logs; echo BACK_TO_MENU\n')
        pid,fd=pty.fork()
        if pid==0:os.execlp('bash','bash',str(runner))
        output=b''
        try:
            deadline=time.monotonic()+5
            while b'LOG_READY' not in output and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]:output+=os.read(fd,4096)
            self.assertIn(b'LOG_READY',output);os.write(fd,b'\x03')
            while b'BACK_TO_MENU' not in output and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]:
                    try:output+=os.read(fd,4096)
                    except OSError:break
            self.assertIn(b'BACK_TO_MENU',output)
        finally:
            try:os.killpg(pid,signal.SIGTERM)
            except ProcessLookupError:pass
            os.waitpid(pid,0);os.close(fd)

class CoreTests(unittest.TestCase):
    @unittest.skipUnless(CORE and Path(CORE).is_file(),'set CADDY_TEST_BINARY for real core checks')
    def test_generated_and_legacy_configuration(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);site=root/'site';site.mkdir()
            r=subprocess.run(['bash','-c',f'source {shlex.quote(str(SCRIPT))}; data_tool new "$1" proxy.example.com "" "$1/site"', '_',d],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            env=dict(os.environ,HOME=d,XDG_DATA_HOME=d+'/data',XDG_CONFIG_HOME=d+'/config')
            for path in (root/'Caddyfile',root/'legacy.Caddyfile'):
                if path.name.startswith('legacy'):
                    path.write_text('{\n http_port 23456\n}\n:34567, proxy.example.com:34567 {\n route {\n forward_proxy {\n basic_auth old-user old-pass\n hide_ip\n hide_via\n probe_resistance\n }\n reverse_proxy https://demo.cloudreve.org\n }\n}\n')
                r=subprocess.run([CORE,'validate','--config',str(path),'--adapter','caddyfile'],capture_output=True,text=True,env=env)
                self.assertEqual(r.returncode,0,r.stderr)
                r=subprocess.run([CORE,'adapt','--config',str(path),'--adapter','caddyfile'],capture_output=True,text=True,env=env)
                self.assertEqual(r.returncode,0,r.stderr)
                adapted=root/'adapted.json';adapted.write_text(r.stdout)
                command=f'source {shlex.quote(str(SCRIPT))}; data_tool export "$1/adapted.json" "$1/missing" "$1/missing" HK "$1/clients"'
                r=subprocess.run(['bash','-c',command,'_',d],capture_output=True,text=True,env=env)
                self.assertEqual(r.returncode,0,r.stderr)
                needed=subprocess.run(['bash','-c',f'source {shlex.quote(str(SCRIPT))}; data_tool site-needed "$1/adapted.json" "$1/site"','_',d],capture_output=True,text=True)
                self.assertEqual(needed.returncode,0,needed.stderr)
                self.assertEqual(needed.stdout.strip(),'no' if path.name.startswith('legacy') else 'yes')
                value=(root/'clients').read_text()
                self.assertIn(':34567#HK' if path.name.startswith('legacy') else '@proxy.example.com#HK',value)
                if path.name.startswith('legacy'): self.assertIn('old-user:old-pass@',value)
                else:
                    config=json.loads(adapted.read_text())
                    self.assertEqual(config['apps']['http'].get('http_port',80),80)

if __name__=='__main__':unittest.main()

