"""Tests for lib/vm-monitor.py against a fake QEMU monitor on a Unix socket."""
import importlib.util
import io
import os
import socket
import struct
import tempfile
import threading
import unittest
import zlib
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location('vm_monitor', os.path.join(HERE, '..', 'lib', 'vm-monitor.py'))
vm_monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(vm_monitor)

PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'

# Copied from a real session: one browser viewer connected through the websocket.
INFO_VNC_ONE_VIEWER = """default:
  Server: :/run/shm/vnc-ws.sock (unix (Websocket))
    Auth: none (Sub: none)
  Server: :::5900 (ipv6)
    Auth: none (Sub: none)
  Server: 0.0.0.0:5900 (ipv4)
    Auth: none (Sub: none)
  Client: : (unix (Websocket))
    x509_dname: none
    sasl_username: none
"""
INFO_VNC_NOBODY = INFO_VNC_ONE_VIEWER[:INFO_VNC_ONE_VIEWER.index('  Client:')]
INFO_VNC_TWO_VIEWERS = INFO_VNC_ONE_VIEWER + """  Client: 127.0.0.1:41000 (ipv4)
    x509_dname: none
    sasl_username: none
"""


class FakeMonitor(threading.Thread):
    """Speaks just enough of the human monitor protocol: banner, prompt, echo, reply, prompt."""

    def __init__(self, path, handler, echo_suffix=''):
        super().__init__(daemon=True)
        self.handler = handler
        self.echo_suffix = echo_suffix
        self.received = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(1)

    def run(self):
        conn, _ = self.server.accept()
        with conn:
            conn.sendall(b"QEMU 11.1.0 monitor - type 'help' for more information\r\n(qemu) ")
            pending = b''
            while True:
                data = conn.recv(4096)
                if not data:
                    return
                pending += data
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    command = line.decode()
                    self.received.append(command)
                    reply = self.handler(command) or ''
                    echo = command + self.echo_suffix + '\r\n'
                    conn.sendall((echo + reply.replace('\n', '\r\n') + '(qemu) ').encode())


class MonitorTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(setattr, vm_monitor, 'SOCKET', vm_monitor.SOCKET)
        vm_monitor.SOCKET = os.path.join(self.tmp.name, 'monitor.sock')

    def serve(self, handler, **kwargs):
        fake = FakeMonitor(vm_monitor.SOCKET, handler, **kwargs)
        self.addCleanup(fake.server.close)
        fake.start()
        return fake

    def command(self, *commands):
        with vm_monitor.Monitor() as monitor:
            return [monitor.command(command) for command in commands]

    def run_main(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            vm_monitor.main(list(argv))
        return out.getvalue()


class CommandTest(MonitorTestCase):
    def test_reply_comes_back_without_echo_and_prompt(self):
        fake = self.serve(lambda cmd: 'VM status: running\n')
        self.assertEqual(self.command('info status'), ['VM status: running'])
        self.assertEqual(fake.received, ['info status'])

    def test_terminal_escape_codes_in_the_echo_are_dropped(self):
        self.serve(lambda cmd: 'VM status: running\n', echo_suffix='\x1b[K\x1b[D')
        self.assertEqual(self.command('info status'), ['VM status: running'])

    def test_multi_line_reply_keeps_its_lines_and_indentation(self):
        self.serve(lambda cmd: INFO_VNC_ONE_VIEWER)
        self.assertEqual(self.command('info vnc'), [INFO_VNC_ONE_VIEWER.rstrip('\n')])

    def test_a_command_without_output_gives_an_empty_reply(self):
        self.serve(lambda cmd: '')
        self.assertEqual(self.command('device_del bt0'), [''])

    def test_several_commands_on_one_connection(self):
        self.serve(lambda cmd: f'reply to {cmd}\n')
        self.assertEqual(self.command('first', 'second'), ['reply to first', 'reply to second'])

    def test_hmp_joins_its_arguments_into_one_command(self):
        fake = self.serve(lambda cmd: 'ok\n')
        self.assertEqual(self.run_main('hmp', 'device_add', 'usb-host,vendorid=0x8087,id=bt0'), 'ok\n')
        self.assertEqual(fake.received, ['device_add usb-host,vendorid=0x8087,id=bt0'])


class ViewerCountTest(MonitorTestCase):
    def count(self, info_vnc):
        fake = self.serve(lambda cmd: info_vnc)
        count = self.run_main('vnc-clients')
        self.assertEqual(fake.received, ['info vnc'])
        return count

    def test_nobody_is_watching(self):
        self.assertEqual(self.count(INFO_VNC_NOBODY), '0\n')

    def test_one_browser_viewer(self):
        self.assertEqual(self.count(INFO_VNC_ONE_VIEWER), '1\n')

    def test_two_viewers(self):
        self.assertEqual(self.count(INFO_VNC_TWO_VIEWERS), '2\n')


def make_ppm(width, height):
    pixels = bytes((x * 40 + y * 10 + c) % 256 for y in range(height) for x in range(width) for c in range(3))
    return f'P6\n{width} {height}\n255\n'.encode() + pixels, pixels


def read_png(data):
    """Returns (width, height, bit depth, colour type, raw scanlines) and checks every CRC."""
    if not data.startswith(PNG_SIGNATURE):
        raise AssertionError('not a PNG')
    position, header, scanlines = len(PNG_SIGNATURE), None, b''
    while position < len(data):
        length, tag = struct.unpack('>I4s', data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        (crc,) = struct.unpack('>I', data[position + 8 + length:position + 12 + length])
        if crc != zlib.crc32(tag + body) & 0xffffffff:
            raise AssertionError(f'bad CRC in {tag}')
        if tag == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif tag == b'IDAT':
            scanlines += body
        position += 12 + length
    return header[:4] + (zlib.decompress(scanlines),)


class ScreendumpTest(MonitorTestCase):
    def test_ppm_becomes_a_valid_png_with_the_same_pixels(self):
        ppm, pixels = make_ppm(3, 2)
        width, height, depth, colour, raw = read_png(vm_monitor.ppm_to_png(ppm))
        self.assertEqual((width, height, depth, colour), (3, 2, 8, 2))
        rows = [raw[y * 10:(y + 1) * 10] for y in range(2)]
        self.assertEqual([row[0] for row in rows], [0, 0])
        self.assertEqual(b''.join(row[1:] for row in rows), pixels)

    def test_png_written_by_qemu_is_kept_as_it_is(self):
        target = os.path.join(self.tmp.name, 'screen.png')
        png = PNG_SIGNATURE + b'whatever qemu wrote'

        def handler(command):
            if command == f'screendump {target} -f png':
                with open(target, 'wb') as out:
                    out.write(png)

        fake = self.serve(handler)
        self.run_main('screendump', target)
        with open(target, 'rb') as result:
            self.assertEqual(result.read(), png)
        self.assertEqual(fake.received, [f'screendump {target} -f png'])

    def test_falls_back_to_ppm_when_qemu_cannot_write_png(self):
        target = os.path.join(self.tmp.name, 'screen.png')
        ppm, _ = make_ppm(4, 3)

        def handler(command):
            if command == f'screendump {target}.ppm':
                with open(target + '.ppm', 'wb') as out:
                    out.write(ppm)
            return 'unsupported format\n' if command.endswith('-f png') else ''

        self.serve(handler)
        self.run_main('screendump', target)
        with open(target, 'rb') as result:
            self.assertEqual(read_png(result.read())[:2], (4, 3))
        self.assertFalse(os.path.exists(target + '.ppm'))

    def test_a_stale_screenshot_is_not_mistaken_for_a_new_one(self):
        target = os.path.join(self.tmp.name, 'screen.png')
        ppm, _ = make_ppm(2, 2)
        with open(target, 'wb') as stale:
            stale.write(PNG_SIGNATURE + b'from an earlier call')

        def handler(command):
            if command == f'screendump {target}.ppm':
                with open(target + '.ppm', 'wb') as out:
                    out.write(ppm)

        self.serve(handler)
        self.run_main('screendump', target)
        with open(target, 'rb') as result:
            self.assertEqual(read_png(result.read())[:2], (2, 2))


class UsageTest(unittest.TestCase):
    def test_unknown_arguments_exit_with_the_usage_text(self):
        for argv in ([], ['hmp'], ['screendump'], ['vnc-clients', 'extra'], ['bogus']):
            with self.subTest(argv=argv), self.assertRaises(SystemExit) as raised:
                vm_monitor.main(argv)
            self.assertIn('vnc-clients', str(raised.exception.code))


if __name__ == '__main__':
    unittest.main()
