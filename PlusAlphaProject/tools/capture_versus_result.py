"""Ten-second offline match-result discovery; no input, pause or RAM writes."""
import argparse
from collections import Counter
import datetime
import json
from pathlib import Path
import time
import zipfile

from observe_versus_mode import request

RAM_LO, RAM_HI = 0x1D0000, 0x1E0000
SECONDS = 10.0
PAGE_SIZE = 2048


def archive_capture(output, winner):
    stamp = datetime.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S-%f')
    archive = output.resolve() / f'versus-result-{winner}-{stamp}.zip'
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(output.iterdir()):
            if path.is_file() and path.suffix.lower() != '.zip':
                bundle.write(path, arcname=path.name)
    return archive


def number(value):
    return int(value, 0) if isinstance(value, str) else int(value)


def ranges_equal(left, right):
    return [(r['slot'], number(r['lo']), number(r['hi'])) for r in left] == [
        (r['slot'], number(r['lo']), number(r['hi'])) for r in right]


def frame_entries(query, lo, hi, warnings):
    """The existing server pages by frame, not sequence; split full pages."""
    if hi < lo:
        return []
    page = query('wtrace_dump', addr_lo=hex(RAM_LO), addr_hi=hex(RAM_HI),
                 frame_lo=lo, frame_hi=hi, count=PAGE_SIZE)
    if page['emitted'] < PAGE_SIZE:
        return page['entries']
    if lo == hi:
        warnings.add(f'Frame {lo}: lote de {page["emitted"]} escritas; completude nao garantida nesse frame.')
        return page['entries']
    mid = (lo + hi) // 2
    return frame_entries(query, lo, mid, warnings) + frame_entries(query, mid + 1, hi, warnings)


def increment_candidates(entries):
    # These are arithmetic candidates, NOT a claim of match/round victories.
    counts = Counter((e['addr'], e['w'], e['pc']) for e in entries
                     if number(e['new']) == number(e['old']) + 1 and e.get('dma_ch', -1) < 0)
    return [dict(addr=addr, width=width, pc=pc, occurrences=count)
            for (addr, width, pc), count in sorted(counts.items(), key=lambda item: (item[1], item[0]))]


def capture(args):
    query = lambda cmd, **kw: request(args.port, cmd, **kw)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    warnings, entries = set(), []
    original, added, expected = None, None, None
    status = dict(complete=False, requested_seconds=SECONDS, error=None, warnings=[])
    metadata = dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    expected_winner=args.winner, declared_kind=args.kind,
                    port=args.port, ram_lo=hex(RAM_LO), ram_hi=hex(RAM_HI))
    try:
        registers = query('get_registers')
        baseline = query('read_ram', addr=hex(RAM_LO), len=RAM_HI-RAM_LO)
        before = bytes.fromhex(baseline['hex'])
        if len(before) != RAM_HI-RAM_LO:
            raise RuntimeError('Leitura de RAM incompleta.')
        if before[0x39B8] != 1 or before[0xC9D0] != 1:
            raise RuntimeError('Prepare o gameplay Versus antes de iniciar a captura.')
        frozen = query('capture_freeze')
        if frozen.get('freeze_frame', 0) or frozen.get('frozen'):
            raise RuntimeError('Outro diagnostico congelou/agendou o historico; configuracao preservada.')
        metadata['before_registers'] = registers
        metadata['overlay_before'] = query('overlay_loader_status')
        original = query('wtrace_ranges')['ranges']
        if not any(number(r['lo']) <= RAM_LO and number(r['hi']) >= RAM_HI for r in original):
            added = query('wtrace_arm', lo=hex(RAM_LO), hi=hex(RAM_HI))
            expected = original + [dict(slot=added['slot'], lo=hex(RAM_LO), hi=hex(RAM_HI))]
        (output / 'before.bin').write_bytes(before)
        stats = query('wtrace_stats')
        start_seq = last_total = stats['total']
        start_frame = next_frame = query('get_registers')['frame']
        metadata.update(start_frame=start_frame, start_seq=start_seq)
        started = time.monotonic()
        deadline = started + SECONDS
        print('CAPTURA ATIVA: 10 segundos. Execute o golpe final e pule o replay.', flush=True)
        with (output / 'writes.jsonl').open('x', encoding='utf-8') as stream:
            def collect(end_frame):
                nonlocal next_frame, last_total
                stats_now = query('wtrace_stats')
                if stats_now['total'] < last_total:
                    raise RuntimeError('Historico reiniciado durante a captura.')
                if stats_now['oldest_seq'] > last_total:
                    warnings.add('Anel de escritas sobrescrito entre consultas; possivel perda de eventos.')
                if end_frame < next_frame - 1:
                    raise RuntimeError('Frame recuou: save/load ou rewind durante a coleta.')
                batch = [e for e in frame_entries(query, next_frame, end_frame, warnings)
                         if e['seq'] >= start_seq and number(e['old']) != number(e['new'])]
                for event in batch:
                    stream.write(json.dumps(event) + '\n')
                stream.flush()
                entries.extend(batch)
                next_frame = end_frame + 1
                last_total = stats_now['total']

            while time.monotonic() < deadline:
                time.sleep(min(.05, max(0, deadline-time.monotonic())))
                if time.monotonic() >= deadline:
                    break
                # Only completed frames: no partial frame is skipped on next poll.
                collect(query('get_registers')['frame'] - 1)
            closing = query('get_registers')
            metadata['end_registers'] = closing
            if closing['frame'] <= start_frame:
                warnings.add('O jogo nao avancou frames durante a janela.')
            status['observed_seconds'] = time.monotonic() - started
            collect(closing['frame'] - 1)
        print('Janela encerrada. Exportando os dados e restaurando o diagnostico...', flush=True)
        after = query('read_ram', addr=hex(RAM_LO), len=RAM_HI-RAM_LO)
        after_bytes = bytes.fromhex(after['hex'])
        if len(after_bytes) != RAM_HI-RAM_LO:
            raise RuntimeError('Leitura final de RAM incompleta.')
        (output / 'after.bin').write_bytes(after_bytes)
        metadata['overlay_after'] = query('overlay_loader_status')
        # Resolve live overlay identity for observed writer functions, where available.
        # This is post-window context, not proof of the image live at every write.
        functions = sorted({e['func'] for e in entries if
                            0 < (number(e['func']) & 0x1FFFFFFF) < 0x101000})
        metadata['overlay_candidates_after'] = {
            pc: query('overlay_candidates', pc=pc) for pc in functions[:32]}
        if len(functions) > 32:
            warnings.add('Contexto de overlay limitado a 32 funcoes; preservar codigo/hash antes de atribuir significado.')
        (output / 'increment_candidates.json').write_text(
            json.dumps(increment_candidates(entries), indent=2), encoding='utf-8')
        status['complete'] = not warnings
        status['changed_writes'] = len(entries)
    except KeyboardInterrupt:
        status['error'] = 'Captura interrompida; dados parciais preservados.'
    except Exception as error:
        status['error'] = str(error)
    finally:
        if added is not None:
            try:
                current = query('wtrace_ranges')['ranges']
                if not ranges_equal(current, expected):
                    raise RuntimeError('Faixas alteradas por outro observador; remocao automatica cancelada.')
                query('wtrace_disarm', slot=added['slot'])
            except Exception as error:
                status['complete'] = False
                warnings.add(f'Nao foi possivel remover a faixa temporaria: {error}')
        status['warnings'] = sorted(warnings)
        (output / 'metadata.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
        (output / 'status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')
    print(f'Dados: {output}', flush=True)
    if status['error']:
        print(status['error'], flush=True)
    for warning in status['warnings']:
        print(f'ATENCAO: {warning}', flush=True)
    try:
        archive = archive_capture(output, args.winner)
        print(f'ARQUIVO PARA ANALISE: "{archive}"', flush=True)
    except Exception as error:
        status['error'] = f'Falha ao empacotar captura: {error}'
        status['complete'] = False
        (output / 'status.json').write_text(json.dumps(status, indent=2), encoding='utf-8')
        print(f'RELATORIO PARA ANALISE: "{output / "status.json"}"', flush=True)
    return 0 if status['complete'] else (1 if status['error'] else 2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=4531)
    parser.add_argument('--winner', choices=('P1', 'P2', 'unknown'), default='unknown')
    parser.add_argument('--kind', choices=('match', 'round'), default='match')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--package-only', action='store_true', help='Empacota uma captura existente sem consultar o jogo.')
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('Porta invalida.')
    if args.package_only:
        if not (args.output / 'status.json').is_file():
            parser.error('Pasta sem status.json de captura.')
        print(f'ARQUIVO PARA ANALISE: "{archive_capture(args.output, args.winner)}"', flush=True)
        return 0
    return capture(args)


if __name__ == '__main__':
    raise SystemExit(main())
