"""seed_preview_overlay: logica pura com palavras sinteticas + casos reais (pulados sem disco)."""
import struct
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import seed_preview_overlay as so  # noqa: E402
import coverage_metric as cm  # noqa: E402

BASE = 0x80100000
ADDIU_SP_M8 = 0x27BDFFF8
JR_RA = 0x03E00008


def image(words, base=BASE):
    return so.Image('SINT', struct.pack(f'<{len(words)}I', *words), base)


def analyze(words, addr, entries=()):
    img = image(words)
    tables = (so.static_references(img),) + so.table_references(img, set(entries))[0:1] + \
        so.table_references(img, set(entries))[1:]
    return so.analyze_entry(img, addr, set(entries), set(), tables)


class Synthetic(unittest.TestCase):
    def test_prologue_entry_ok(self):
        # f: addiu sp; nop; jr ra; nop
        r = analyze([ADDIU_SP_M8, 0, JR_RA, 0], BASE)
        self.assertEqual((r['borda'], r['erros'], r['palavras']), ('prologo', [], 4))

    def test_after_jr_ra_delay_is_ok(self):
        r = analyze([JR_RA, 0, 0x24020001, JR_RA, 0], BASE + 8)
        self.assertEqual((r['borda'], r['erros'], r['palavras']), ('jr_ra+delay', [], 3))

    def test_padding_between_delay_and_entry_is_ok(self):
        r = analyze([JR_RA, 0, 0x00FFFFFF, 0x24020001, JR_RA, 0], BASE + 12)
        self.assertEqual((r['borda'], r['erros']), ('jr_ra+delay+padding', []))

    def test_interior_without_evidence_is_bad_border(self):
        r = analyze([ADDIU_SP_M8, 0x24020001, 0x24030002, JR_RA, 0], BASE + 8)
        self.assertEqual(r['borda'], 'interior')
        self.assertIn('borda_ruim', r['erros'])

    def test_branch_target_is_block_leader(self):
        # beq zero,zero,+2 ; nop ; nop ; addiu ; jr ra ; nop
        r = analyze([0x10000002, 0, 0, 0x24020001, JR_RA, 0], BASE + 12)
        self.assertEqual((r['borda'], r['erros']), ('lider_de_bloco', []))

    def test_invalid_word_and_invalid_delay_slot(self):
        r = analyze([ADDIU_SP_M8, 0x00FFFFFF, JR_RA, 0], BASE)
        self.assertIn('palavra_invalida', r['erros'])
        # jr ra cujo delay slot e outro salto
        r = analyze([ADDIU_SP_M8, JR_RA, JR_RA, 0], BASE)
        self.assertIn('delay_invalido', r['erros'])

    def test_store_into_overlay_text_is_smc(self):
        # lui t0,0x8010 ; sw t1,0x10(t0) ; jr ra ; nop  -> escreve em 0x80100010 (texto)
        r = analyze([ADDIU_SP_M8, 0x3C088010, 0xAD090010, JR_RA, 0, 0, 0, 0, 0], BASE)
        self.assertIn('smc', r['erros'])
        self.assertTrue(r['stores_no_texto'])

    def test_exit_code_follows_errors_and_strict_warnings(self):
        ok = {'entradas': [{'erros': [], 'avisos': ['tabela_fora_do_extent']}]}
        self.assertEqual(so.exit_code(ok), 0)
        self.assertEqual(so.exit_code(ok, strict=True), 1)
        self.assertEqual(so.exit_code({'entradas': [{'erros': ['smc'], 'avisos': []}]}), 1)


class CheckProfile(unittest.TestCase):
    NAME = 'OVL/SINT.OVL'
    BODY = struct.pack('<4I', ADDIU_SP_M8, 0, JR_RA, 0)
    PHYS = BASE & 0x1FFFFFFF

    def variants(self, body):
        import zlib
        return [{'ranges': [(self.PHYS, len(body))], 'crc': zlib.crc32(body) & 0xFFFFFFFF,
                 'entry': self.PHYS}]

    def test_declared_entry_with_matching_variant_passes(self):
        files = {self.NAME: (self.BODY, self.PHYS)}
        rows = so.check_profile([(self.NAME, [BASE])], files, self.variants(self.BODY))
        self.assertEqual([r[2] for r in rows], [True])

    def test_variant_of_other_file_fails(self):
        other = struct.pack('<4I', ADDIU_SP_M8, 1, JR_RA, 0)  # mesmo endereco, bytes diferentes
        files = {self.NAME: (self.BODY, self.PHYS)}
        rows = so.check_profile([(self.NAME, [BASE])], files, self.variants(other))
        self.assertFalse(rows[0][2])
        self.assertIn('nenhuma variante', rows[0][3])

    def test_entry_missing_from_matching_variant_fails(self):
        files = {self.NAME: (self.BODY, self.PHYS)}
        rows = so.check_profile([(self.NAME, [BASE + 8])], files, self.variants(self.BODY))
        self.assertFalse(rows[0][2])
        self.assertIn('sem variante casada', rows[0][3])

    def test_missing_disc_file_fails(self):
        rows = so.check_profile([(self.NAME, [BASE])], {}, self.variants(self.BODY))
        self.assertFalse(rows[0][2])

    def test_declared_entries_reads_interior_and_extents(self):
        import json
        import tempfile
        profile = {'images': [
            {'interior_entries_by_file': {'OVL/PL0E_1.OVL': ['0x800466e4']}},
            {'extents': [{'file': 'OVL3/MOV.OVL', 'entries': ['0x800e8994']},
                         {'file': 'OVL3/QUES.PAC'}]}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'overlays.json'
            path.write_text(json.dumps(profile))
            self.assertEqual(so.declared_entries(path),
                             [('OVL/PL0E_1.OVL', [0x800466E4]), ('OVL3/MOV.OVL', [0x800E8994])])


class NoMatchingVariantWarning(unittest.TestCase):
    BODY = struct.pack('<4I', ADDIU_SP_M8, 0, JR_RA, 0)
    PHYS = BASE & 0x1FFFFFFF

    def report(self, variants):
        import io
        from contextlib import redirect_stdout
        rep = so.preview('OVL/SINT.OVL', [BASE], {'OVL/SINT.OVL': (self.BODY, self.PHYS)},
                         variants, {})
        out = io.StringIO()
        with redirect_stdout(out):
            so.print_report(rep, 'sintetico')
        return rep, out.getvalue()

    def test_zero_matching_variants_warns_and_fails_only_in_strict(self):
        rep, text = self.report([])
        self.assertEqual(rep['variantes_casadas'], 0)
        self.assertIn('AVISO: nenhuma variante', text)
        self.assertEqual(so.exit_code(rep), 0)
        self.assertEqual(so.exit_code(rep, strict=True), 1)

    def test_matching_variant_has_no_warning(self):
        import zlib
        variants = [{'ranges': [(self.PHYS, 16)], 'crc': zlib.crc32(self.BODY) & 0xFFFFFFFF,
                     'entry': self.PHYS}]
        rep, text = self.report(variants)
        self.assertEqual(rep['variantes_casadas'], 1)
        self.assertNotIn('AVISO: nenhuma variante', text)
        self.assertEqual(so.exit_code(rep, strict=True), 0)


def real_context():
    try:
        cue = cm.disc_cue_from_game_toml(cm.need(so.PROJECT_ROOT / 'game.toml', 'game.toml'))
        dispatcher = cm.latest_build_overlays()
        if dispatcher is None:
            return None
        return (so.load_files(cue),
                cm.parse_overlays_static(dispatcher.read_text(encoding='utf-8', errors='replace')),
                cm.load_extents(so.PROJECT_ROOT / 'aot/overlays.json'))
    except (cm.InputMissing, OSError):
        return None


CONTEXT = real_context()


@unittest.skipIf(CONTEXT is None, 'disco ou overlays_static.c ausentes')
class RealDisc(unittest.TestCase):
    def test_mov_8994_closure_and_border(self):
        files, variants, extents = CONTEXT
        rep = so.preview('OVL3/MOV.OVL', [0x800E8994], files, variants, extents)
        row = rep['entradas'][0]
        self.assertEqual(row['erros'], [])
        self.assertEqual(row['borda'], 'jr_ra+delay+padding')
        self.assertEqual(row['palavras'], 12)  # 8 ate o primeiro jr ra + o ramo alternativo
        self.assertEqual(row['palavras_enderecos'][0], '0x800E8994')
        self.assertEqual(so.exit_code(rep), 0)

    def test_mov_interior_word_is_bad_border(self):
        files, variants, extents = CONTEXT
        rep = so.preview('OVL3/MOV.OVL', [0x800E8998], files, variants, extents)
        self.assertIn('borda_ruim', rep['entradas'][0]['erros'])
        self.assertEqual(so.exit_code(rep), 1)

    def test_ques_table_outside_old_extent(self):
        files, variants, extents = CONTEXT
        old = (0x800E64D8, 0x2FA4)
        rep = so.preview('OVL3/QUES.PAC', [0x800E6F4C], files, variants, extents, old)
        row = rep['entradas'][0]
        self.assertIn('tabela_fora_do_extent', row['avisos'])
        self.assertEqual(row['referencias_tabela_fora_do_extent'], ['jr@0x800E6AB4'])
        self.assertEqual(so.exit_code(rep), 1)
        new = so.preview('OVL3/QUES.PAC', [0x800E6F4C, 0x800E6FCC], files, variants,
                         {'OVL3/QUES.PAC': (0xE64D8, 0x3134)})
        self.assertEqual(so.exit_code(new), 0)
        self.assertTrue(all(r['borda'] == 'lider_de_bloco' for r in new['entradas']))

    def test_pl0e_p1_p2_mirror(self):
        files, variants, extents = CONTEXT
        rep = so.preview('OVL/PL0E_1.OVL', [0x800466E4, 0x80046768], files, variants, extents)
        self.assertEqual(so.exit_code(rep), 0)
        for row in rep['entradas']:
            self.assertTrue(row['espelho']['presente'])
            self.assertEqual(row['espelho']['palavras_divergentes'], [])
        self.assertEqual(rep['entradas'][0]['espelho']['espelho_pc'], '0x800900E4')


if __name__ == '__main__':
    unittest.main()
