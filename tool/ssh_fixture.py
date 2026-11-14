"""Loopback-only test SSH/SFTP server. Ephemeral credentials, no real shell."""
import asyncio, asyncssh, tempfile, pathlib, time
class Server(asyncssh.SSHServer):
    def connection_requested(self, dest_host, dest_port, orig_host, orig_port):
        return dest_host == '127.0.0.1' and dest_port == 22345
    def begin_auth(self, username): return True
    def password_auth_supported(self): return True
    def validate_password(self, username, password):
        return username == 'fastcat-test' and password == 'loopback-only-test'
async def process(p):
    if p.command and p.command.startswith('# FASTCAT_METRICS_V1'):
        tick=int(time.monotonic()*100)
        p.stdout.write(f'FC_SYSTEM\nLinux fixture x86_64\nFC_MODEL\nFixture CPU\nFC_CORES\n4\nFC_CPU\ncpu {tick} 0 50 {tick*4} 0 0 0 0\nFC_MEMORY\nMemTotal: 16384000 kB\nMemAvailable: 8192000 kB\nFC_DISK\n/dev/root 1048576 524288 524288 50% /\nFC_NETWORK\n eth0: {tick*100} 0 0 0 0 0 0 0 {tick*50} 0 0 0 0 0 0 0\nFC_UPTIME\n3600.00 0\n')
        p.exit(0)
    elif p.command:
        p.stdout.write('FastCat fixture: ' + p.command + '\n')
        p.exit(0)
    else:
        p.stdout.write('FastCat test shell ready\r\n')
        pending=''
        while True:
            try: chunk=await p.stdin.read(4096)
            except asyncssh.TerminalSizeChanged: continue
            if not chunk: break
            pending+=chunk.replace('\r\n','\n').replace('\r','\n')
            while '\n' in pending:
                line,pending=pending.split('\n',1)
                p.stdout.write('echo: '+line+'\r\n')
async def main():
    with tempfile.TemporaryDirectory(prefix='fastcat-sftp-') as root:
        pathlib.Path(root+'/logs/archive').mkdir(parents=True)
        pathlib.Path(root+'/logs/example.log').write_text('log fixture\n')
        with open(root+'/hello.txt','w') as f: f.write('hello FastCat\n')
        server = await asyncssh.create_server(Server,'127.0.0.1',22345,server_host_keys=[asyncssh.generate_private_key('ssh-ed25519')],process_factory=process,sftp_factory=lambda chan:asyncssh.SFTPServer(chan,chroot=root))
        print('FIXTURE_READY 127.0.0.1:22345',flush=True)
        await server.wait_closed()
asyncio.run(main())
