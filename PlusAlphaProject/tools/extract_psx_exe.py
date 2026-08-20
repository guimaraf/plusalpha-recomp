#!/usr/bin/env python3
"""Extrai um PS-X EXE por caminho ISO9660 de uma imagem PS1 Mode 2/2352.

O script lê apenas a primeira faixa de dados referenciada pelo CUE. Ele não
converte a imagem e não toca nas faixas XA/CDDA.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import struct
import sys


RAW_SECTOR_SIZE = 2352
USER_DATA_OFFSET = 24
USER_DATA_SIZE = 2048
PVD_LBA = 16


def resolve_data_track(path: Path) -> Path:
    if path.suffix.lower() != ".cue":
        return path

    cue_text = path.read_text(encoding="utf-8-sig", errors="strict")
    for line in cue_text.splitlines():
        match = re.match(r'^\s*FILE\s+"([^"]+)"\s+BINARY\s*$', line, re.IGNORECASE)
        if match:
            candidate = Path(match.group(1))
            return candidate if candidate.is_absolute() else path.parent / candidate
    raise ValueError(f"Nenhuma linha FILE ... BINARY encontrada em {path}")


def read_user_sector(handle, lba: int) -> bytes:
    handle.seek(lba * RAW_SECTOR_SIZE + USER_DATA_OFFSET)
    data = handle.read(USER_DATA_SIZE)
    if len(data) != USER_DATA_SIZE:
        raise ValueError(f"Leitura incompleta no setor {lba}")
    return data


def root_directory(handle) -> tuple[int, int]:
    pvd = read_user_sector(handle, PVD_LBA)
    if pvd[0] != 1 or pvd[1:6] != b"CD001" or pvd[6] != 1:
        raise ValueError("Primary Volume Descriptor ISO9660 não encontrado")
    record = pvd[156:190]
    return struct.unpack_from("<I", record, 2)[0], struct.unpack_from("<I", record, 10)[0]


def list_directory(handle, directory_lba: int, directory_size: int) -> list[dict[str, object]]:
    sectors = (directory_size + USER_DATA_SIZE - 1) // USER_DATA_SIZE
    directory = b"".join(
        read_user_sector(handle, directory_lba + index) for index in range(sectors)
    )

    offset = 0
    entries: list[dict[str, object]] = []
    while offset < directory_size:
        record_len = directory[offset]
        if record_len == 0:
            offset = ((offset // USER_DATA_SIZE) + 1) * USER_DATA_SIZE
            continue
        record = directory[offset : offset + record_len]
        if len(record) != record_len or record_len < 34:
            raise ValueError("Registro ISO9660 inválido no diretório raiz")
        name_len = record[32]
        raw_name = record[33 : 33 + name_len]
        if raw_name not in (b"\x00", b"\x01"):
            name = raw_name.decode("ascii").split(";", 1)[0]
            entries.append({
                "name": name,
                "lba": struct.unpack_from("<I", record, 2)[0],
                "size": struct.unpack_from("<I", record, 10)[0],
                "is_directory": bool(record[25] & 0x02),
            })
        offset += record_len
    return entries


def find_file(handle, wanted: str) -> tuple[int, int]:
    parts = [part for part in re.split(r"[\\/]", wanted) if part]
    if not parts:
        raise ValueError("caminho ISO9660 vazio")

    directory_lba, directory_size = root_directory(handle)
    for index, part in enumerate(parts):
        match = next(
            (
                entry
                for entry in list_directory(handle, directory_lba, directory_size)
                if str(entry["name"]).upper() == part.upper()
            ),
            None,
        )
        if match is None:
            raise FileNotFoundError(
                f"componente {part!r} não encontrado ao resolver {wanted!r}"
            )

        is_last = index == len(parts) - 1
        if is_last:
            if bool(match["is_directory"]):
                raise IsADirectoryError(f"{wanted} identifica um diretório")
            return int(match["lba"]), int(match["size"])
        if not bool(match["is_directory"]):
            raise NotADirectoryError(f"{part!r} não é um diretório em {wanted!r}")
        directory_lba = int(match["lba"])
        directory_size = int(match["size"])

    raise FileNotFoundError(wanted)


def extract(disc: Path, name: str, output: Path) -> tuple[int, str, int]:
    data_track = resolve_data_track(disc).resolve()
    if not data_track.is_file():
        raise FileNotFoundError(f"Faixa de dados não encontrada: {data_track}")

    with data_track.open("rb") as handle:
        lba, size = find_file(handle, name)
        remaining = size
        chunks: list[bytes] = []
        sector = lba
        while remaining:
            chunk = read_user_sector(handle, sector)[:remaining]
            chunks.append(chunk)
            remaining -= len(chunk)
            sector += 1

    payload = b"".join(chunks)
    if not payload.startswith(b"PS-X EXE"):
        raise ValueError(f"{name} não possui assinatura PS-X EXE")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    return len(payload), hashlib.sha1(payload).hexdigest().upper(), lba


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disc", required=True, type=Path, help="CUE ou BIN Mode 2/2352")
    parser.add_argument(
        "--name", required=True,
        help="Caminho ISO9660, por exemplo SLUS_005.84 ou PAC/LOGO.EXE",
    )
    parser.add_argument("--output", required=True, type=Path, help="Arquivo local de saída")
    args = parser.parse_args()

    try:
        size, sha1, lba = extract(args.disc, args.name, args.output)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"erro: {error}", file=sys.stderr)
        return 1

    print(f"extraído: {args.output}")
    print(f"tamanho: {size}")
    print(f"sha1: {sha1}")
    print(f"lba: {lba}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
