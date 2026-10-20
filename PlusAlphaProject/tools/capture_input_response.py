"""5 s preparation + 5 s offline causal capture. Never injects input or builds.

Discovery returns hypotheses, not measured animation latency. Measure requires a
reviewed profile derived from a real discovery capture and game-code inspection.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import socket
import time

BUTTONS = {'square': 0x8000, 'triangle': 0x1000, 'circle': 0x2000,
           'cross': 0x4000, 'l1': 0x400, 'r1': 0x800, 'l2': 0x100, 'r2': 0x200}


def number(value):
    return int(value, 0) if isinstance(value, str) else int(value)


def command(port, payload):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as connection:
        connection.settimeout(10)
        connection.sendall((json.dumps({'id': 1, **payload}) + '\n').encode())
        data = bytearray()
        while len(data) < 2 * 1024 * 1024:
            block = connection.recv(65536)
            if not block:
                break
            data.extend(block)
            try:
                reply = json.loads(data)
            except (ValueError, UnicodeDecodeError):
                continue
            if not reply.get('ok') or 'error' in reply:
                raise RuntimeError(f'Diagnostico recusou: {reply}')
            return reply
    raise RuntimeError('Resposta incompleta do diagnostico.')


def read_pages(port, events=False):
    cursor, records = 0, []
    for _ in range(65537):
        page = command(port, {'cmd': 'input_response_dump', 'cursor': cursor,
                              'events': int(events)})
        records.extend(page['records'])
        if page['done']:
            return records
        if page['next'] <= cursor:
            raise RuntimeError('Cursor de exportacao nao avancou.')
        cursor = page['next']
    raise RuntimeError('Exportacao excedeu o limite de paginas.')


def first_action_candidates(capture):
    presses = sorted((e for e in capture['events'] if e['kind'] == 1), key=lambda e: e['qpc'])
    if not presses:
        return []
    start = presses[0]['qpc']
    end = presses[1]['qpc'] if len(presses) > 1 else float('inf')
    return [r for r in capture['candidates'] if start <= r['qpc'] < end]


def profile_config(path):
    profile = json.loads(path.read_text(encoding='utf-8'))
    if profile.get('verified') is not True:
        raise ValueError('Perfil ainda nao validado; execute discovery e revise os PCs/estados.')
    evidence = (path.parent / profile['evidence_file']).resolve()
    raw = evidence.read_bytes()
    if hashlib.sha256(raw).hexdigest() != profile['evidence_sha256']:
        raise ValueError('Hash da captura de evidencia difere do perfil.')
    capture = json.loads(raw)
    if capture['player'] != profile['player'] or capture['button'] != profile['button']:
        raise ValueError('Player/botao do perfil diferem da captura de evidencia.')
    if (capture['mode'] != 'discovery' or capture['status']['overflow'] or
            capture['status']['cancelled'] or capture['status']['phase'] != 3 or
            capture['status']['presses'] < 1 or capture['status']['unexpected_inputs']):
        raise ValueError('Evidencia deve ser uma descoberta completa, sem overflow.')
    params = {key: number(profile[key]) for key in (
        'state_addr', 'state_width', 'idle_value', 'attack_value', 'state_pc',
        'input_addr', 'input_width', 'input_mask', 'input_value', 'input_pc')}
    if any(value < 0 or value > 0xFFFFFFFF for value in params.values()):
        raise ValueError('Campo do perfil fora de uint32.')
    if params['input_width'] not in (1, 2, 4) or params['state_width'] not in (1, 2, 4):
        raise ValueError('Largura do marcador precisa ser 1, 2 ou 4 bytes.')
    if params['input_value'] & ~params['input_mask']:
        raise ValueError('input_value precisa estar contido em input_mask.')
    first_candidates = first_action_candidates(capture)
    presses = sorted((e for e in capture['events'] if e['kind'] == 1), key=lambda e: e['qpc'])
    next_press_frame = presses[1]['frame'] if len(presses) > 1 else float('inf')
    for prefix in ('state', 'input'):
        addr = params[f'{prefix}_addr'] & 0x1fffffff
        pc, width = params[f'{prefix}_pc'], params[f'{prefix}_width']
        candidates = [r for r in first_candidates if
                      r['addr'] == addr and r['pc'] == pc and r['kind'] == width]
        if not candidates:
            raise ValueError(f'Marcador {prefix} nao consta da captura de evidencia.')
        if prefix == 'state' and not any(
                r['old'] == params['idle_value'] and r['value'] == params['attack_value']
                and not r['pre_changes'] and r['return_pc'] != 0
                and r['frame'] <= r['return_frame'] < next_press_frame
                and r['return_pc'] == number(profile['idle_return_pc']) for r in candidates):
            raise ValueError('Exige estado estavel, transicao de ataque e PC de retorno na evidencia.')
    return params, profile


def analyze(status, events, mode):
    reasons = []
    if status['phase'] != 3 or status['cancelled']:
        reasons.append('captura incompleta ou cancelada')
    if status['overflow']:
        reasons.append('overflow; dados incompletos')
    if status['unexpected_inputs']:
        reasons.append('input extra ou botao durante preparacao')
    if status['presses'] < 1:
        reasons.append('nenhum toque no botao escolhido foi registrado durante a captura')
    if mode == 'discovery':
        warnings = []
        if status['presses'] > 1:
            warnings.append(f"{status['presses']} toques registrados; revisar somente o primeiro ciclo, antes do segundo toque")
        return {'valid_capture': not reasons, 'valid_measurement': False,
                'measurement_status': 'pending_marker_review',
                'presses_registered': status['presses'], 'reasons': reasons, 'warnings': warnings,
                'latency_frames': None, 'latency_ms': None}
    if status['presses'] != 1:
        reasons.append('a medicao requer exatamente um toque no botao escolhido')
    duration = (status['stop_qpc'] - status['start_qpc']) / status['frequency']
    fps = ((status['stop_frame'] - status['start_frame']) / duration) if duration > 0 else 0
    if not 55 <= fps <= 65:
        reasons.append('cadencia distante de 60 FPS; nao representa o teste pretendido')
    if not status['initial_idle']:
        reasons.append('estado inicial nao corresponde ao idle validado')
    host = [e for e in events if e['kind'] == 1]
    accepted = [e for e in events if e['kind'] == 2]
    attack = [e for e in events if e['kind'] == 3]
    # Do not choose a convenient pair from ambiguous transitions.
    if len(host) != 1 or len(accepted) != 1 or len(attack) != 1:
        reasons.append('marcadores ausentes ou ambiguos; exige um de cada')
    elif not host[0]['qpc'] <= accepted[0]['qpc'] <= attack[0]['qpc']:
        reasons.append('ordem causal incorreta')
    if reasons:
        return {'valid_measurement': False, 'reasons': reasons,
                'latency_frames': None, 'latency_ms': None}
    a, b, c = host[0], accepted[0], attack[0]
    scale = 1000 / status['frequency']
    return {'valid_measurement': True, 'reasons': [],
            'latency_frames': c['frame'] - a['frame'],
            'latency_ms': (c['qpc'] - a['qpc']) * scale,
            'game_accept_to_state_frames': c['frame'] - b['frame'],
            'game_accept_to_state_ms': (c['qpc'] - b['qpc']) * scale,
            'capture_fps': fps,
            'elapsed_frame_equivalents': (c['qpc'] - a['qpc']) * scale * fps / 1000,
            'frame_counter_note': 'latency_frames e diferenca de indices; nao duracao exata em frames',
            'scope': 'SIO host latch ate transicao interna validada; nao button-to-photon'}


def collection_summary(status):
    # Acquisition integrity only. No matching, latency calculation or statistics.
    reasons = []
    if status['phase'] != 3 or status['cancelled']:
        reasons.append('captura incompleta ou cancelada')
    if status['overflow']:
        reasons.append('overflow; dados incompletos')
    if status['unexpected_inputs']:
        reasons.append('input extra ou botao durante preparacao')
    if not status['initial_idle']:
        reasons.append('estado inicial diferente do perfil')
    if status['presses'] < 1:
        reasons.append('nenhum input registrado')
    return dict(valid_capture=not reasons, valid_measurement=False,
                measurement_status='deferred_offline_analysis', reasons=reasons,
                presses_registered=status['presses'], latency_ms=None, latency_frames=None)


def result_exit_code(result, mode):
    valid = (result['valid_capture'] if mode == 'discovery' or
             result.get('measurement_status') == 'deferred_offline_analysis'
             else result['valid_measurement'])
    return 0 if valid else 2


def countdown(seconds, text):
    for left in range(seconds, 0, -1):
        print(f'{text}: {left}s', flush=True)
        time.sleep(1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('discovery', 'measure'), default='discovery')
    parser.add_argument('--port', type=int, default=4531)
    parser.add_argument('--player', type=int, choices=(1, 2), default=1)
    parser.add_argument('--button', choices=BUTTONS,
                        help='botao PS1 correspondente ao soco fraco no jogo')
    parser.add_argument('--warmup', type=int, choices=range(1, 31), default=5)
    parser.add_argument('--seconds', type=int, choices=range(1, 31), default=5)
    parser.add_argument('--lo', type=number, default=0)
    parser.add_argument('--hi', type=number, default=0x200000)
    parser.add_argument('--profile', type=Path)
    parser.add_argument('--output', type=Path,
                        help='pasta nova; nunca sobrescreve coleta anterior')
    parser.add_argument('--collect-only', action='store_true',
                        help='measure: exportar varios inputs sem calcular latencia; analise posterior')
    parser.add_argument('--review', type=Path,
                        help='reanalisar capture.json existente, sem conectar ao jogo nem alterar arquivos')
    args = parser.parse_args(argv)
    if args.collect_only and (args.mode != 'measure' or args.review):
        parser.error('--collect-only exige --mode measure e nao aceita --review')
    if args.review:
        saved = json.loads(args.review.read_text(encoding='utf-8'))
        if saved.get('collect_only'):
            parser.error('Coleta bruta multipla: requer analise offline por tentativa; --review atual aceita medicao unica.')
        result = analyze(saved['status'], saved['events'], saved['mode'])
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return result_exit_code(result, saved['mode'])
    if not args.button or not args.output:
        parser.error('a captura exige --button e --output')
    profile = None
    params = {}
    if args.mode == 'discovery' and args.profile:
        parser.error('--profile so se aplica a --mode measure')
    if args.mode == 'measure':
        if not args.profile:
            parser.error('--mode measure exige --profile validado')
        params, profile = profile_config(args.profile)
        if profile.get('button') != args.button or profile.get('player') != args.player:
            parser.error('Botao/player diferem do perfil validado.')
        # Addresses/PCs may exceed signed JSON int range in the C command parser.
        params = {key: hex(value) for key, value in params.items()}
    if args.output.exists():
        parser.error('--output precisa ser uma pasta nova')
    # Fail before arming if the folder cannot be created.
    args.output.mkdir(parents=True)
    armed = False
    try:
        before = command(args.port, {'cmd': 'input_response_status'})
        if before.get('probe_version') != 1:
            raise RuntimeError('Build sem o protocolo input_response v1.')
        arm = command(args.port, {'cmd': 'input_response_arm',
            'discovery': int(args.mode == 'discovery'), 'warmup_ms': args.warmup * 1000,
            'capture_ms': args.seconds * 1000, 'port': args.player - 1,
            'button_mask': BUTTONS[args.button], 'lo': hex(args.lo), 'hi': hex(args.hi), **params})
        armed = True
        (args.output / 'arm.json').write_text(json.dumps(arm, indent=2), encoding='utf-8')
        if profile:
            print('MEDICAO OFFLINE: use o personagem, player e botao do perfil.', flush=True)
            print('Escopo: SIO ate selecao interna da animacao; nao inclui exibicao no monitor.', flush=True)
        print('Foque a janela do jogo. Fique parado; solte todos os botoes.', flush=True)
        countdown(args.warmup, 'Preparacao')
        if args.collect_only:
            print('\aAGORA: toques curtos no soco fraco, separados por cerca de 1 segundo. Espere voltar ao parado.', flush=True)
        else:
            print('\aAGORA: um toque curto no soco fraco, depois fique parado.', flush=True)
        countdown(args.seconds, 'Captura')
        status = None
        for _ in range(15):
            status = command(args.port, {'cmd': 'input_response_status'})
            if status['phase'] == 3:
                break
            time.sleep(.2)
        if status['phase'] != 3:
            raise RuntimeError('Janela nao terminou; jogo pausado ou sem frames?')
        armed = False
        print('Captura encerrada. Exportando dados; nenhuma nova amostra e registrada.', flush=True)
        events = read_pages(args.port, events=True)
        candidates = read_pages(args.port) if args.mode == 'discovery' else []
        result = (collection_summary(status) if args.collect_only
                  else analyze(status, events, args.mode))
        capture = {'schema': 1, 'mode': args.mode, 'player': args.player,
                   'button': args.button, 'collect_only': args.collect_only,
                   'status': status, 'events': events,
                   'candidates': candidates, 'profile': profile, 'analysis': result}
        data = json.dumps(capture, indent=2, ensure_ascii=False).encode('utf-8')
        (args.output / 'capture.json').write_bytes(data)
        (args.output / 'capture.sha256').write_text(hashlib.sha256(data).hexdigest() + '\n')
        if args.collect_only and events:
            with (args.output / 'events.csv').open('w', newline='', encoding='utf-8-sig') as f:
                writer = csv.DictWriter(f, fieldnames=list(events[0]))
                writer.writeheader()
                writer.writerows(events)
        if candidates:
            ordered = sorted(candidates, key=lambda r: (r['pre_changes'] != 0,
                                                       r['pre_writes'] == 0, r['qpc']))
            with (args.output / 'candidates.csv').open('w', newline='', encoding='utf-8-sig') as f:
                writer = csv.DictWriter(f, fieldnames=list(ordered[0]))
                writer.writeheader()
                for row in ordered:
                    display = dict(row)
                    for key in ('addr', 'pc', 'old', 'value', 'return_pc'):
                        display[key] = f'0x{row[key]:08X}'
                    writer.writerow(display)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        print('Coleta:', args.output.resolve())
        if args.mode == 'discovery':
            print('Envie capture.json para analise dos candidatos. Nenhum PC foi presumido.')
        return result_exit_code(result, args.mode)
    finally:
        if armed:
            try:
                command(args.port, {'cmd': 'input_response_stop'})
            except (OSError, RuntimeError):
                print('Nao foi possivel desarmar por TCP; a janela expira quando o runtime avancar frames.')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, KeyError) as exc:
        raise SystemExit(f'Coleta falhou: {exc}')
