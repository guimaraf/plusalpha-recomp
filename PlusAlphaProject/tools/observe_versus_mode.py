"""Read-only state/write capture; never builds, injects input or changes RAM.

The RAM windows cover the observed scene/mode fields and unclassified neighbours.
The collector records raw evidence; it never infers a mode or changes visibility.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import socket
import time

WINDOWS = ((0x1D39B8, 0x1D39D8), (0x1DC9D0, 0x1DCA10))


def request(port, cmd, **args):
    with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
        sock.settimeout(5)
        sock.sendall((json.dumps(dict(id=1, cmd=cmd, **args)) + '\n').encode())
        with sock.makefile('rb') as stream:
            for _ in range(16):
                line = stream.readline(2 * 1024 * 1024)
                if not line:
                    break
                reply = json.loads(line)
                if reply.get('id') == 1:
                    if not reply.get('ok'):
                        raise RuntimeError(f'{cmd}: {reply}')
                    return reply
    raise RuntimeError(f'{cmd}: resposta incompleta')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_record(stream, kind, **data):
    stream.write(json.dumps(dict(time=now(), kind=kind, **data)) + '\n')
    stream.flush()


def drain(port, stream, cursor):
    stats = request(port, 'wtrace_trans_stats')
    if stats['total'] < cursor:
        raise RuntimeError('Historico reiniciado; inicie outra captura.')
    if cursor < stats['oldest_seq']:
        raise RuntimeError('Historico sobrescrito; captura incompleta.')
    for lo, hi in WINDOWS:
        next_seq = cursor
        while next_seq < stats['total']:
            page = request(port, 'wtrace_trans_dump', addr_lo=hex(lo),
                           addr_hi=hex(hi), seq_lo=str(next_seq), count=512)
            entries = [e for e in page['entries'] if e['seq'] < stats['total']]
            if entries:
                write_record(stream, 'writes', lo=hex(lo), hi=hex(hi), entries=entries)
            if page['emitted'] < 512 or not entries:
                break
            next_seq = entries[-1]['seq'] + 1
    return stats['total']


def capture(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    status = dict(complete=False, interrupted=False, error=None)
    cursor = None
    try:
        with (output / 'trace.jsonl').open('x', encoding='utf-8') as stream:
            stats = request(args.port, 'wtrace_trans_stats')
            write_record(stream, 'start', label=args.label, port=args.port,
                         windows=WINDOWS, trace_stats=stats)
            if stats.get('env_error') or stats.get('env_ranges', 0) < 2:
                raise RuntimeError('Reabra uma instancia dedicada com PSX_WTRACE_BOOT_RANGES='
                                   '0x1d39b8-0x1d39d8,0x1dc9d0-0x1dca10')
            write_record(stream, 'overlay_status', data=request(args.port, 'overlay_loader_status'))
            if args.exe:
                with args.exe.open('rb') as binary:
                    digest = hashlib.file_digest(binary, 'sha256').hexdigest()
                write_record(stream, 'executable', path=str(args.exe.resolve()), sha256=digest)
            cursor = stats['total']
            last = None
            end = time.monotonic() + args.seconds
            print(f'Observador ativo: {output}', flush=True)
            print('Navegue pelos modos. Marcadores: subcomando mark em outro terminal.', flush=True)
            while time.monotonic() < end:
                reads = [request(args.port, 'read_ram', addr=hex(lo), len=hi-lo)
                         for lo, hi in WINDOWS]
                signature = tuple(r['hex'] for r in reads)
                if signature != last:
                    registers = request(args.port, 'get_registers')
                    write_record(stream, 'state', reads=reads, registers=registers)
                    # Context only: sampled PC is not the PC that wrote a value.
                    write_record(stream, 'overlay_status', data=request(args.port, 'overlay_loader_status'))
                    print(f"scene={reads[0]['hex'][:2]} candidate={reads[1]['hex'][:2]} "
                          f"frame={registers['frame']}", flush=True)
                    last = signature
                cursor = drain(args.port, stream, cursor)
                time.sleep(args.interval_ms / 1000)
            cursor = drain(args.port, stream, cursor)
            status['complete'] = True
    except KeyboardInterrupt:
        status['interrupted'] = True
        status['error'] = 'Interrompida; dados parciais preservados.'
    except Exception as error:
        status['error'] = str(error)
        raise
    finally:
        (output / 'status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')
    return 0 if status['complete'] else 1


def mark(args):
    if not (args.output / 'trace.jsonl').is_file():
        raise ValueError('Pasta de captura inexistente.')
    with (args.output / 'markers.jsonl').open('a', encoding='utf-8') as stream:
        write_record(stream, 'marker', label=args.label,
                     registers=request(args.port, 'get_registers'),
                     reads=[request(args.port, 'read_ram', addr=hex(lo), len=hi-lo)
                            for lo, hi in WINDOWS])
    print(args.label)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='action', required=True)
    for action in ('capture', 'mark'):
        sub = subs.add_parser(action)
        sub.add_argument('--port', type=int, default=4533)
        sub.add_argument('--output', type=Path, required=True)
        sub.add_argument('--label', required=True)
        if action == 'capture':
            sub.add_argument('--seconds', type=float, default=180)
            sub.add_argument('--interval-ms', type=int, default=500)
            sub.add_argument('--exe', type=Path)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('Porta invalida.')
    if args.action == 'capture' and (not 0 < args.seconds <= 3600 or args.interval_ms < 100):
        parser.error('Duracao deve ser 0..3600 s; intervalo minimo 100 ms.')
    return capture(args) if args.action == 'capture' else mark(args)


if __name__ == '__main__':
    raise SystemExit(main())
