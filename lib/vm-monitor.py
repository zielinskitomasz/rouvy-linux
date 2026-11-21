"""QEMU monitor client. Runs inside the VM container, fed over `docker exec ... python3 -`.

    hmp <command...>     print the reply of one monitor command
    screendump <path>    write a PNG of the VM screen to <path> (inside the container)
    vnc-clients          print how many viewers are connected to the VM screen
"""
import os
import re
import socket
import struct
import sys
import zlib

SOCKET = '/run/shm/monitor.sock'
PROMPT = b'(qemu) '
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')


class Monitor:
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(SOCKET)
        self._read_until_prompt()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.sock.close()

    def _read_until_prompt(self):
        buf = b''
        try:
            while not buf.endswith(PROMPT):
                chunk = self.sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
        except socket.timeout:
            pass
        return buf

    def command(self, cmd):
        self.sock.sendall((cmd + '\n').encode())
        out = ANSI.sub('', self._read_until_prompt().decode(errors='replace')).replace('\r', '')
        lines = [line for line in out.split('\n') if line.strip() and not line.startswith('(qemu)')]
        # The monitor echoes the typed command back before its reply.
        if lines and cmd in lines[0]:
            lines = lines[1:]
        return '\n'.join(lines)


def ppm_to_png(ppm):
    _, width, height, _ = ppm.split(maxsplit=3)[:4]
    width, height = int(width), int(height)
    pixels = ppm[len(ppm) - width * height * 3:]
    rows = b''.join(b'\x00' + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))

    def chunk(tag, body):
        return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 6))
            + chunk(b'IEND', b''))


def is_png(path):
    if not os.path.exists(path):
        return False
    with open(path, 'rb') as image:
        return image.read(4) == b'\x89PNG'


def screendump(monitor, path):
    if os.path.exists(path):
        os.remove(path)
    monitor.command(f'screendump {path} -f png')
    if is_png(path):
        return
    # QEMU builds without libpng only write PPM.
    ppm = path + '.ppm'
    monitor.command(f'screendump {ppm}')
    with open(ppm, 'rb') as src, open(path, 'wb') as dst:
        dst.write(ppm_to_png(src.read()))
    os.remove(ppm)


def main(argv):
    if len(argv) >= 2 and argv[0] == 'hmp':
        with Monitor() as monitor:
            print(monitor.command(' '.join(argv[1:])))
    elif len(argv) == 2 and argv[0] == 'screendump':
        with Monitor() as monitor:
            screendump(monitor, argv[1])
    elif argv == ['vnc-clients']:
        with Monitor() as monitor:
            print(len(re.findall(r'^\s*Client:', monitor.command('info vnc'), re.MULTILINE)))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
