"""Stage an existing Windows Release build. Never builds or downloads anything."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def imported_dlls(binary, objdump):
    result = subprocess.run([str(objdump), '-p', str(binary)], check=True,
                            capture_output=True, text=True)
    return re.findall(r'DLL Name:\s*(\S+)', result.stdout)


def collect_dlls(binary, build, ucrt, system, objdump):
    pending, visited, found = [binary], set(), {}
    while pending:
        for name in imported_dlls(pending.pop(), objdump):
            key = name.lower()
            if key in visited:
                continue
            visited.add(key)
            if key.startswith(('api-ms-win-', 'ext-ms-win-')):
                continue
            # Windows owns system imports; never redistribute its DLLs.
            if (system / name).is_file():
                continue
            source = next((p / name for p in (build, ucrt) if (p / name).is_file()), None)
            if source is None:
                raise ValueError(f'Dependencia DLL ausente: {name}')
            found[key] = source
            pending.append(source)
    return list(found.values())


def archive_paths(output, archive):
    output, archive = output.resolve(), archive.resolve()
    partial, checksum = Path(str(archive) + '.partial'), Path(str(archive) + '.sha256')
    if archive == output or output in archive.parents:
        raise ValueError('ZIP deve ficar fora da pasta distribuivel.')
    if any(p.exists() for p in (archive, partial, checksum)):
        raise ValueError('ZIP, arquivo parcial ou checksum existente preservado.')
    return archive, partial, checksum


def create_archive(output, archive):
    """Archive only the staged manifest inventory, never a build directory."""
    output = output.resolve()
    archive, partial, checksum = archive_paths(output, archive)
    manifest = json.loads((output / 'release-manifest.json').read_text(encoding='utf-8'))
    expected = manifest['files']
    actual = {p.relative_to(output).as_posix(): p for p in output.rglob('*') if p.is_file()}
    if set(actual) != set(expected) | {'release-manifest.json'}:
        raise ValueError('Pasta foi modificada ou esta incompleta; gere um pacote novo antes de compactar.')
    for name, path in actual.items():
        if path.is_symlink() or (name in expected and sha256_file(path) != expected[name]):
            raise ValueError(f'Integridade do pacote divergente: {name}')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(partial, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, path in sorted(actual.items()):
            zipped.write(path, arcname=output.name + '/' + name)
    # Verify the compressed bytes against the staged hashes before publishing.
    with zipfile.ZipFile(partial) as zipped:
        if zipped.testzip() is not None:
            raise ValueError('Verificacao CRC do ZIP falhou; arquivo parcial preservado.')
        for name, path in actual.items():
            digest = hashlib.sha256()
            with zipped.open(output.name + '/' + name) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            if digest.hexdigest() != sha256_file(path):
                raise ValueError(f'Verificacao do ZIP falhou: {name}')
    # Windows rename refuses an existing destination; earlier outputs stay intact.
    if archive.exists():
        raise ValueError('ZIP apareceu durante o empacotamento; arquivo existente preservado.')
    partial.rename(archive)
    with checksum.open('x', encoding='utf-8') as stream:
        stream.write(sha256_file(archive) + '  ' + archive.name + '\n')
    print(f'ZIP verificado: {archive} ({archive.stat().st_size / 1024**2:.2f} MiB)')


def package(build, output, ucrt, archive=None):
    project = Path(__file__).resolve().parents[1]
    repo = project.parent
    build, output, ucrt = build.resolve(), output.resolve(), ucrt.resolve()
    if archive is not None:
        archive_paths(output, archive)
        if build == archive.resolve() or build in archive.resolve().parents:
            raise ValueError('ZIP deve ficar fora da pasta de build.')
    # A new directory only: never replace builds, releases or personal data.
    if output.exists() or output == build or build in output.parents or output in build.parents:
        raise ValueError('A saida deve ser uma pasta nova e separada da build.')
    for source_root in (repo / 'psxrecomp', repo / 'recomp-ui'):
        if source_root.resolve() in output.parents:
            raise ValueError('A saida nao pode ficar dentro dos fontes de dependencias.')
    cache = (build / 'CMakeCache.txt').read_text(encoding='utf-8')
    for setting in ('CMAKE_BUILD_TYPE:STRING=Release', 'PSX_DEBUG_TOOLS:BOOL=OFF',
                    'PSX_SETUP_WIZARD:BOOL=OFF', 'PSX_NETPLAY:BOOL=ON',
                    'BUILD_DECOUPLED_LAUNCHER:BOOL=OFF', 'PSX_RECOMP_UI:BOOL=ON',
                    'PSX_STATIC_RUNTIME:BOOL=ON', 'RNET_ENABLE_ICE:BOOL=ON'):
        if setting not in cache.splitlines():
            raise ValueError(f'Build release esperada: {setting}')
    binary = build / 'exPlusAlpha.exe'
    objdump, strip = ucrt / 'objdump.exe', ucrt / 'strip.exe'
    required = [binary, build / 'exPlusAlpha.execution.json', build / 'game.toml',
                build / 'sfexp.png', build / 'psx_game_version.txt', objdump, strip,
                build / 'psx_mod_catalog_psx-runtime.txt',
                build / 'psx_mod_catalog_psx-runtime.excluded.txt']
    for path in required:
        if not path.is_file():
            raise ValueError(f'Arquivo obrigatorio ausente: {path}')
    for path in (build / 'assets', build / 'mods' / 'bundled'):
        if not path.is_dir():
            raise ValueError(f'Diretorio obrigatorio ausente: {path}')
        if any(p.is_symlink() for p in path.rglob('*')):
            raise ValueError(f'Links nao permitidos no pacote: {path}')
    system = Path(os.environ['SystemRoot']) / 'System32'
    binaries = [binary]
    if (build / 'xdelta3.exe').is_file():
        binaries.append(build / 'xdelta3.exe')
    dlls = {}
    for executable in binaries:
        for path in collect_dlls(executable, build, ucrt, system, objdump):
            dlls[path.name.lower()] = path
    spec = importlib.util.spec_from_file_location('release_stage', repo / 'psxrecomp/tools/release_stage.py')
    staging = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(staging)
    output.mkdir(parents=True)
    (output / 'PACKAGE_INCOMPLETE.txt').write_text('Pacote incompleto; nao distribuir.\n')
    for name in ('exPlusAlpha.exe', 'game.toml', 'sfexp.png', 'psx_game_version.txt'):
        shutil.copy2(build / name, output / name)
    for source in binaries[1:] + list(dlls.values()):
        shutil.copy2(source, output / source.name)
    # Strip only the COPY. Keep exports and all source build/debug artifacts.
    subprocess.run([str(strip), '--strip-debug', str(output / binary.name)], check=True)
    shutil.copytree(build / 'assets', output / 'assets')
    # Pass only bundled catalog data, never installed mods or personal state.
    bundled = output / 'mods' / 'bundled'
    shutil.copytree(build / 'mods' / 'bundled', bundled)
    expected = set((build / 'psx_mod_catalog_psx-runtime.txt').read_text().splitlines()) - {''}
    actual = {p.name for p in bundled.iterdir() if p.is_dir()}
    excluded = set((build / 'psx_mod_catalog_psx-runtime.excluded.txt').read_text().splitlines()) - {''}
    if expected != actual or actual & excluded:
        raise ValueError('Catalogo de mods difere do declarado pela build.')
    staging.stage_execution(str(output / binary.name), str(build / 'exPlusAlpha.execution.json'))
    # Preserve third-party notices, including font and library licenses.
    roots = [repo / 'psxrecomp', repo / 'recomp-ui', build / '_deps']
    notices = output / 'licenses'
    for index, root in enumerate(roots):
        if not root.is_dir():
            continue
        for directory, dirs, names in os.walk(root, followlinks=False):
            dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__', 'node_modules')
                       and not (Path(directory) / d).is_symlink()]
            for name in names:
                path = Path(directory) / name
                if path.is_symlink() or not any(
                        token in name.lower() for token in ('license', 'copying', 'notice', 'ofl')):
                    continue
                target = notices / str(index) / path.relative_to(root)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    (output / 'LEIA-ME.txt').write_text(
        'Ex Plus Alpha - Windows x64\n\n'
        'Abra exPlusAlpha.exe e selecione seu disco original (CUE/BIN) e sua\n'
        'BIOS SCPH1001.BIN no launcher. Estes arquivos nao acompanham o pacote.\n'
        'Nao sao necessarios MSYS2, Python, CMake ou compiladores para jogar.\n'
        'Extraia para uma pasta gravavel: configuracoes e saves sao criados ao usar.\n'
        'O pacote inclui launcher, lobby online e rollback.\n', encoding='utf-8')
    files = {p.relative_to(output).as_posix(): sha256_file(p)
             for p in sorted(output.rglob('*'))
             if p.is_file() and p.name != 'PACKAGE_INCOMPLETE.txt'}
    (output / 'release-manifest.json').write_text(
        json.dumps({'schema': 1, 'files': files}, indent=2) + '\n', encoding='utf-8')
    (output / 'PACKAGE_INCOMPLETE.txt').unlink()
    size = sum(p.stat().st_size for p in output.rglob('*') if p.is_file())
    print(f'Release preparada: {output} ({len(files)} arquivos + manifesto, {size / 1024**2:.2f} MiB)')
    if archive is not None:
        create_archive(output, archive)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ucrt-bin', type=Path, required=True)
    parser.add_argument('--zip-path', type=Path)
    args = parser.parse_args()
    try:
        package(args.build, args.output, args.ucrt_bin, args.zip_path)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Release recusada: {error}\n')
