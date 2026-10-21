#!/usr/bin/env python3
"""Create one private local identity; never regenerate it for routine updates."""
from pathlib import Path
import os, subprocess, secrets, tempfile, json
root=Path.home()/'Library/Application Support/HomeDeckSigning'
root.mkdir(mode=0o700,parents=True,exist_ok=True)
os.chmod(root,0o700)
kc=root/'signing.keychain-db'
config=root/'identity.json'
def run(args,**kw):
    try:
        return subprocess.run(args,check=True,capture_output=True,text=True,**kw).stdout
    except subprocess.CalledProcessError:
        raise SystemExit('Local signing setup failed; sensitive command arguments withheld.') from None
if config.exists():
    print('Existing signing identity retained; never regenerate it for an update.'); raise SystemExit
password=secrets.token_urlsafe(48)
old=run(['security','list-keychains','-d','user'])
import shlex
search=shlex.split(old)
try:
    run(['security','create-keychain','-p',password,str(kc)])
finally:
    run(['security','list-keychains','-d','user','-s',*search])
with tempfile.TemporaryDirectory(dir=root) as tmp:
    p=Path(tmp)
    (p/'openssl.cnf').write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=HomeDeck Local Code Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
    run(['/usr/bin/openssl','req','-new','-x509','-newkey','rsa:3072','-nodes','-days','3650','-config',str(p/'openssl.cnf'),'-keyout',str(p/'key.pem'),'-out',str(p/'cert.pem')])
    env=dict(os.environ,HOMEDECK_P12_PASSWORD=password)
    run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(p/'key.pem'),'-in',str(p/'cert.pem'),'-out',str(p/'identity.p12'),'-name','HomeDeck Local Code Signing','-passout','env:HOMEDECK_P12_PASSWORD'],env=env)
    run(['security','import',str(p/'identity.p12'),'-k',str(kc),'-P',password,'-x','-T','/usr/bin/codesign'])
    fingerprint=run(['/usr/bin/openssl','x509','-in',str(p/'cert.pem'),'-fingerprint','-sha1','-noout']).strip().split('=')[1].replace(':','')
    (root/'certificate.pem').write_bytes((p/'cert.pem').read_bytes())
config.write_text(json.dumps({'identity':fingerprint,'keychain':str(kc),'password':password},indent=2)+'\n')
os.chmod(config,0o600)
run(['security','add-trusted-cert','-r','trustRoot','-p','codeSign','-k',str(kc),str(root/'certificate.pem')])
print('Created dedicated local signing identity: '+fingerprint)
