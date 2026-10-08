"""Exercise the published Caddy's authenticated HTTPS CONNECT path locally."""
import http.server
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest

CORE=os.environ.get('CADDY_TEST_BINARY','')

@unittest.skipUnless(CORE and Path(CORE).is_file(),'set CADDY_TEST_BINARY for proxy traffic')
class ProxyTests(unittest.TestCase):
    def test_authenticated_tls_connect_and_rejected_credentials(self):
        class Origin(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200);self.end_headers();self.wfile.write(b'naive-proxy-traffic-ok')
            def log_message(self,*args):pass
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            site=root/'site';site.mkdir()
            page=Path(__file__).resolve().parents[1]/'index.html'
            (site/'index.html').write_bytes(page.read_bytes())
            origin=http.server.ThreadingHTTPServer(('127.0.0.1',0),Origin)
            thread=threading.Thread(target=origin.serve_forever,daemon=True);thread.start()
            self.addCleanup(origin.server_close);self.addCleanup(origin.shutdown)
            with socket.socket() as reserve:
                reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1]
            config=root/'Caddyfile'
            subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1',
                            '-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1',
                            '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost'],check=True,capture_output=True)
            config.write_text('''{
 admin off
 auto_https off
}
:PORT, localhost:PORT {
 tls CERT KEY
 route {
  forward_proxy {
   basic_auth test-user test-password
   hide_ip
   hide_via
   probe_resistance
   acl {
    allow 127.0.0.1
   }
  }
  file_server {
   root SITE
  }
 }
}
'''.replace('PORT',str(port)).replace('CERT',str(root/'cert.pem')).replace('KEY',str(root/'key.pem')).replace('SITE',str(site)))
            env=dict(os.environ,HOME=directory,XDG_DATA_HOME=directory+'/data',XDG_CONFIG_HOME=directory+'/config')
            with open(root/'caddy.log','w+') as log:
                process=subprocess.Popen([CORE,'run','--config',str(config),'--adapter','caddyfile'],env=env,stdout=log,stderr=log)
                try:
                    deadline=time.monotonic()+8
                    while time.monotonic()<deadline:
                        if process.poll() is not None:
                            log.seek(0);self.fail(log.read())
                        try:
                            with socket.create_connection(('127.0.0.1',port),timeout=.2):break
                        except OSError:time.sleep(.05)
                    public=['curl','--silent','--show-error','--max-time','5','--noproxy','*','--cacert',str(root/'cert.pem')]
                    result=subprocess.run(public+['--fail',f'https://localhost:{port}/'],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertEqual(result.stdout,page.read_text())
                    result=subprocess.run(public+['--output',os.devnull,'--write-out','%{http_code}',f'https://localhost:{port}/missing-file'],capture_output=True,text=True)
                    self.assertEqual(result.stdout,'404')
                    base=['curl','--silent','--show-error','--max-time','5','--noproxy','','--proxy-insecure','--proxy',f'https://localhost:{port}','--proxytunnel']
                    url=f'http://127.0.0.1:{origin.server_port}/'
                    result=subprocess.run(base+['--proxy-user','test-user:test-password',url],capture_output=True,text=True)
                    if result.returncode:
                        log.seek(0);self.fail(result.stderr+'\n'+log.read())
                    self.assertEqual(result.stdout,'naive-proxy-traffic-ok')
                    result=subprocess.run(base+['--proxy-user','test-user:incorrect',url],capture_output=True,text=True)
                    self.assertNotEqual(result.returncode,0)
                    self.assertNotIn('naive-proxy-traffic-ok',result.stdout)
                finally:
                    process.terminate()
                    try:process.wait(timeout=5)
                    except subprocess.TimeoutExpired:process.kill();process.wait()

