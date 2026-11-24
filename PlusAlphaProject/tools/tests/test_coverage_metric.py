"""Metrica de cobertura: testes com fixtures sinteticas (sem disco real)."""
import importlib.util
import zlib
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    'coverage_metric', Path(__file__).resolve().parents[1] / 'coverage_metric.py')
cm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cm)


def excl_doc(items, lo='0x80100000', hi='0x80100100'):
    return {'exe': {'text_lo': lo, 'text_hi': hi},
            'exclusions': [{'lo': a, 'hi': b, 'category': c, 'reason': 'x'}
                           for a, b, c in items]}


class RangesTest(unittest.TestCase):
    def test_duplicate_ranges_count_once_legacy_double(self):
        funcs, ranges = cm.parse_ranges(
            '# c\nF 80100000\nF 80100000\nR 80100000 10\nR 80100000 10\nR 80100010 8\n')
        self.assertEqual({0x80100000}, funcs)
        words = cm.covered_word_set(ranges, 0x80100000, 0x80100100)
        self.assertEqual(6, len(words))
        self.assertEqual(10, sum(ln // 4 for _, ln in ranges))


class DispatchTest(unittest.TestCase):
    def test_ignores_extern_comments_and_pair_table(self):
        text = (
            'extern void func_80100000(CPUState* cpu);\n'
            '/* {0x80100004u, 0x0u, 1u, 1u, func_80100004}, */\n'
            '    {0x80100008u, 0x80100008u},\n'
            '    {0x8010000Cu, 0x00000000u, 0u, 1u, func_8010000C},\n')
        self.assertEqual({0x8010000C}, cm.parse_dispatch(text))


class ExclusionTest(unittest.TestCase):
    def test_overlap_rejected(self):
        doc = excl_doc([('0x80100000', '0x80100020', 'padding'),
                        ('0x80100010', '0x80100030', 'dados')])
        with self.assertRaises(cm.ExclusionError):
            cm.load_exclusions(doc)

    def test_outside_text_and_bad_category_rejected(self):
        with self.assertRaises(cm.ExclusionError):
            cm.load_exclusions(excl_doc([('0x80100000', '0x80100200', 'dados')]))
        with self.assertRaises(cm.ExclusionError):
            cm.load_exclusions(excl_doc([('0x80100000', '0x80100010', 'outra')]))

    def test_coverage_inside_exclusion_detected(self):
        t_lo, t_hi, excl = cm.load_exclusions(
            excl_doc([('0x80100000', '0x80100010', 'padding')]))
        m = cm.exe_metrics({1}, [(0x80100008, 16)], {0x80100020}, t_lo, t_hi, excl)
        self.assertEqual(2, m['covered_in_exclusions']['padding'])
        self.assertEqual(64 - 4, m['code_words'])
        self.assertEqual(2, m['covered_words'])  # 0x80100010 e 0x80100014


class CheckTest(unittest.TestCase):
    @staticmethod
    def report(cov=10, ent=5, ov_cov=100, ov_ent=7):
        return {'exe': {'covered_words': cov, 'dispatch_entries': 3, 'functions': 2,
                        'covered_in_exclusions': {'dados': 0}},
                'overlays': {'files': [{'name': 'A', 'covered_words': ov_cov,
                                        'entries': ov_ent}]}}

    def test_regressions_detected_and_equal_or_greater_passes(self):
        base = cm.baseline_from(self.report())
        self.assertEqual([], cm.check(self.report(), base, False))
        self.assertEqual([], cm.check(self.report(cov=11, ov_cov=101, ov_ent=8), base, False))
        errs = cm.check(self.report(cov=9), base, False)
        self.assertTrue(any('exe.covered_words' in e for e in errs))
        errs = cm.check(self.report(ov_cov=99, ov_ent=6), base, False)
        self.assertEqual(2, len(errs))
        self.assertEqual([], cm.check(self.report(ov_cov=1, ov_ent=1), base, True))

    def test_coverage_in_exclusions_fails(self):
        r = self.report()
        r['exe']['covered_in_exclusions'] = {'dados': 1}
        self.assertTrue(cm.check(r, cm.baseline_from(self.report()), False))


class VariantMatchTest(unittest.TestCase):
    def test_match_mismatch_and_outside_window(self):
        base = 0x1000
        data = bytes(range(256)) * 4  # 1024 bytes
        r1, r2 = (0x1000, 16), (0x1100, 8)
        good = zlib.crc32(data[0x100:0x108], zlib.crc32(data[0:16]))
        v_ok = {'ranges': [r1, r2], 'crc': good, 'entry': 0x80001000}
        v_bad = {'ranges': [r1, r2], 'crc': good ^ 1, 'entry': 0x80001000}
        v_out = {'ranges': [(0x1400, 8)], 'crc': 0, 'entry': 0x80001400}
        hit, miss = cm.match_variants([v_ok, v_bad, v_out], data, base)
        self.assertEqual([v_ok], hit)
        self.assertEqual([v_bad], miss)
        m = cm.overlay_metrics([v_ok, v_bad, v_out], [('F', 1, data, base)])
        row = m['files'][0]
        self.assertEqual(6, row['covered_words'])
        self.assertEqual((1, 1, 1), (row['variants_matched'], row['crc_mismatch'],
                                     row['entries']))
        self.assertEqual(2, m['total']['unmatched'])

    def test_parse_overlays_static_entry_mapping(self):
        text = (
            'static const uint32_t psx_ov_static_ranges_00000[] = { 0x00001000u, 0x10u };\n'
            'static const uint32_t psx_ov_static_ranges_00001[] = { 0x00001000u, 0x10u };\n'
            'static const PsxOvVariant psx_ov_variants[2] = {\n'
            '    { psx_ov_static_ranges_00000, 1u, 0x11111111u, f0 },\n'
            '    { psx_ov_static_ranges_00001, 1u, 0x22222222u, f1 },\n};\n'
            'static const PsxOvEntry psx_ov_entries[1] = {\n'
            '    { 0x80001000u, 0u, 2u },\n};\n')
        vs = cm.parse_overlays_static(text)
        self.assertEqual([0x80001000] * 2, [v['entry'] for v in vs])
        self.assertEqual([(0x1000, 0x10)], vs[0]['ranges'])


if __name__ == '__main__':
    unittest.main()
