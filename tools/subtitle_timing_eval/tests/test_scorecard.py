import unittest

from subtitle_timing_eval.srt import Cue
from subtitle_timing_eval import scorecard as sc


def _cues(texts, *, dur=2.0, gap=0.0):
    cues = []
    t = 0.0
    for i, text in enumerate(texts, start=1):
        cues.append(Cue(index=i, start=t, end=t + dur, text=text))
        t += dur + gap
    return cues


class LevenshteinTests(unittest.TestCase):
    def test_identical(self):
        self.assertEqual(sc.levenshtein("abc", "abc"), 0)

    def test_substitution(self):
        self.assertEqual(sc.levenshtein("abc", "abd"), 1)

    def test_empty(self):
        self.assertEqual(sc.levenshtein("", "abc"), 3)
        self.assertEqual(sc.levenshtein("abc", ""), 3)


class ReferenceSimilarityTests(unittest.TestCase):
    def test_cjk_perfect_ignores_punct(self):
        score = sc.reference_similarity_score("今日はいい天気。", "今日は、いい天気", language_code="ja")
        self.assertEqual(score, 100.0)

    def test_cjk_partial(self):
        score = sc.reference_similarity_score("今日はいい天気", "今日は悪い天気", language_code="ja")
        self.assertTrue(0 < score < 100)

    def test_latin_word_level(self):
        score = sc.reference_similarity_score("the cat sat", "the cat sat", language_code="en")
        self.assertEqual(score, 100.0)
        worse = sc.reference_similarity_score("the dog ran", "the cat sat", language_code="en")
        self.assertLess(worse, score)

    def test_empty_reference_returns_none(self):
        self.assertIsNone(sc.reference_similarity_score("abc", "", language_code="en"))


class ConfidenceTests(unittest.TestCase):
    def test_too_few_words_returns_none(self):
        words = [{"probability": 0.9}] * 10
        self.assertIsNone(sc.confidence_from_words(words))

    def test_high_confidence_high_score(self):
        words = [{"probability": 0.95}] * 40
        stats = sc.confidence_from_words(words)
        self.assertIsNotNone(stats)
        score = sc._confidence_score(stats)
        self.assertGreaterEqual(score, 90)

    def test_garbled_low_confidence_low_score(self):
        words = [{"probability": 0.3}] * 40
        stats = sc.confidence_from_words(words)
        score = sc._confidence_score(stats)
        self.assertLess(score, 30)

    def test_low_conf_ratio_penalized(self):
        clean = sc._confidence_score(sc.confidence_from_words([{"probability": 0.85}] * 40))
        mixed_words = ([{"probability": 0.85}] * 20) + ([{"probability": 0.2}] * 20)
        mixed = sc._confidence_score(sc.confidence_from_words(mixed_words))
        self.assertLess(mixed, clean)


class RecognitionScoreTests(unittest.TestCase):
    def test_clean_japanese_scores_well(self):
        cues = _cues(["今日はいい天気ですね", "はいそうです", "とても気持ちいい", "散歩しましょう"])
        words = [{"probability": 0.93}] * 40
        result = sc.recognition_score(candidate_cues=cues, language_code="ja", words=words)
        self.assertIsNotNone(result.score)
        self.assertGreaterEqual(result.score, 80)

    def test_components_renormalize_when_absent(self):
        cues = _cues(["hello world", "this is fine"])
        # No words, no reference, no llm → only structural present.
        result = sc.recognition_score(candidate_cues=cues, language_code="en")
        self.assertEqual(result.components["confidence"], None)
        self.assertEqual(result.components["reference"], None)
        self.assertEqual(result.components["llm"], None)
        self.assertAlmostEqual(result.score, result.components["structural"], places=5)
        self.assertFalse(result.verified)
        self.assertIn("unverified:needsReferenceOrLLM", result.notes)

    def test_reference_marks_verified(self):
        cues = _cues(["今日はいい天気"])
        result = sc.recognition_score(candidate_cues=cues, language_code="ja", reference_text="今日はいい天気")
        self.assertTrue(result.verified)

    def test_romaji_loop_japanese_penalized(self):
        clean = _cues(["今日はいい天気ですね", "とても良い一日"])
        garbled = _cues(["nani nani nani nani", "dare dare dare dare"])
        clean_score = sc.recognition_score(candidate_cues=clean, language_code="ja").score
        garbled_score = sc.recognition_score(candidate_cues=garbled, language_code="ja").score
        self.assertLess(garbled_score, clean_score)

    def test_reference_dominates_when_present(self):
        cues = _cues(["今日はいい天気"])
        good_ref = sc.recognition_score(
            candidate_cues=cues, language_code="ja", reference_text="今日はいい天気"
        ).score
        bad_ref = sc.recognition_score(
            candidate_cues=cues, language_code="ja", reference_text="全然違う文章だよこれは"
        ).score
        self.assertGreater(good_ref, bad_ref)


class AcousticAgreementTests(unittest.TestCase):
    def test_onsets_on_speech_starts_score_high(self):
        segments = [{"start": 0.0, "end": 2.0}, {"start": 3.0, "end": 5.0}]
        onsets = [0.0, 3.0]
        self.assertEqual(sc.acoustic_boundary_agreement(onsets, segments), 100.0)

    def test_onsets_in_middle_score_low(self):
        segments = [{"start": 0.0, "end": 10.0}]
        onsets = [4.0, 6.0]  # both deep inside continuous speech, far from edges
        self.assertEqual(sc.acoustic_boundary_agreement(onsets, segments), 0.0)

    def test_none_when_no_segments(self):
        self.assertIsNone(sc.acoustic_boundary_agreement([1.0], []))


class SegmentationScoreTests(unittest.TestCase):
    def test_internal_only(self):
        cues = _cues(["これは普通の文です", "もう一つの文です"])
        result = sc.segmentation_score(candidate_cues=cues, language_code="ja")
        self.assertIsNotNone(result.score)
        self.assertEqual(result.components["acoustic"], None)
        self.assertNotIn("reference", result.components)
        self.assertFalse(result.verified)

    def test_acoustic_blends_in(self):
        cues = _cues(["a", "b"], dur=2.0)  # onsets 0.0, 4.0
        segments = [{"start": 0.0, "end": 2.0}, {"start": 4.0, "end": 6.0}]
        result = sc.segmentation_score(candidate_cues=cues, language_code="en", speech_segments=segments)
        self.assertIsNotNone(result.components["acoustic"])

    def test_reference_report_is_informational_not_scored(self):
        cues = _cues(["hello", "world"])
        ref = {"strong_boundary_recall": 0.5, "aligned_boundary_f1": 0.5, "temporal_coverage": 0.95, "segment_count_ratio": 1.0}
        result = sc.segmentation_score(candidate_cues=cues, language_code="en", reference_report=ref)
        # reference is NOT a scored component (style-capped) and does NOT mark verified
        self.assertNotIn("reference", result.components)
        self.assertFalse(result.verified)
        self.assertTrue(any("refInfo" in n for n in result.notes))

    def test_acoustic_marks_verified(self):
        cues = _cues(["a", "b"], dur=2.0)
        segments = [{"start": 0.0, "end": 2.0}, {"start": 4.0, "end": 6.0}]
        result = sc.segmentation_score(candidate_cues=cues, language_code="en", speech_segments=segments)
        self.assertTrue(result.verified)


class TranslationScoreTests(unittest.TestCase):
    def test_structural_only_is_capped(self):
        source = _cues(["今日はいい天気", "はいそうです"])
        translated = _cues(["今天天气很好", "是的没错"])
        result = sc.translation_score(source_cues=source, translated_cues=translated)
        self.assertTrue(result.capped)
        self.assertLessEqual(result.score, sc.RUBRIC.translation_structural_only_cap)

    def test_llm_lifts_above_cap(self):
        source = _cues(["今日はいい天気", "はいそうです"])
        translated = _cues(["今天天气很好", "是的没错"])
        result = sc.translation_score(source_cues=source, translated_cues=translated, llm_translation_score=95.0)
        self.assertFalse(result.capped)
        self.assertGreater(result.score, sc.RUBRIC.translation_structural_only_cap)

    def test_repeated_translation_penalized(self):
        source = _cues(["a", "b", "c", "d"])
        repeated = _cues(["同样", "同样", "同样", "同样"])
        clean = _cues(["第一", "第二", "第三", "第四"])
        r = sc.translation_score(source_cues=source, translated_cues=repeated).score
        c = sc.translation_score(source_cues=source, translated_cues=clean).score
        self.assertLess(r, c)

    def test_empty_translation_penalized(self):
        source = _cues(["a", "b", "c", "d"])
        empty = _cues(["译", "", "", ""])
        self.assertLess(sc.translation_score(source_cues=source, translated_cues=empty).score, 60)


class SourceDecisionScoreTests(unittest.TestCase):
    def test_all_correct(self):
        scenarios = [
            {"id": "clean", "platform_available": True, "platform_usable": True, "expected_decision": "platform"},
            {"id": "garbled", "platform_available": True, "platform_usable": False, "local_asr_available": True, "expected_decision": "localASR"},
            {"id": "manual", "manual_available": True, "expected_decision": "manual"},
        ]
        result = sc.source_decision_score(scenarios)
        self.assertEqual(result.score, 100.0)

    def test_partial(self):
        scenarios = [
            {"id": "clean", "platform_available": True, "platform_usable": True, "expected_decision": "platform"},
            {"id": "wrong", "platform_available": True, "platform_usable": False, "local_asr_available": False, "cloud_available": True, "expected_decision": "localASR"},
        ]
        result = sc.source_decision_score(scenarios)
        self.assertEqual(result.score, 50.0)

    def test_no_scenarios(self):
        self.assertIsNone(sc.source_decision_score([]).score)


class SuiteSummaryTests(unittest.TestCase):
    def _sample(self, rec, seg, tr, *, verified=True):
        return sc.SampleScorecard(
            sample_id="s", language_code="ja", category="test",
            dimensions={
                "recognition": sc.DimensionScore("recognition", rec, verified=verified),
                "segmentation": sc.DimensionScore("segmentation", seg, verified=verified),
                "translation": sc.DimensionScore("translation", tr, verified=verified),
            },
        )

    def test_summary_and_gate(self):
        samples = [self._sample(85, 82, 81), self._sample(90, 84, 83)]
        src = sc.DimensionScore("source_decision", 100.0, verified=True)
        summary = sc.suite_summary(samples, src)
        self.assertTrue(summary["dimensions"]["recognition"]["passes_gate"])
        self.assertTrue(summary["all_dimensions_pass"])

    def test_high_but_unverified_does_not_pass_verified_gate(self):
        samples = [self._sample(95, 95, 95, verified=False)]
        summary = sc.suite_summary(samples, None)
        self.assertFalse(summary["all_dimensions_pass"])
        self.assertTrue(summary["all_dimensions_pass_unverified"])
        self.assertEqual(summary["dimensions"]["recognition"]["verified_samples"], 0)

    def test_failing_gate(self):
        samples = [self._sample(50, 40, 60)]
        summary = sc.suite_summary(samples, None)
        self.assertFalse(summary["all_dimensions_pass"])
        self.assertFalse(summary["dimensions"]["recognition"]["passes_gate"])

    def test_render_markdown_smoke(self):
        samples = [self._sample(85, 82, 81)]
        summary = sc.suite_summary(samples, None)
        md = sc.render_markdown(samples, summary)
        self.assertIn("Moongate 字幕质量 Scorecard", md)
        self.assertIn("识别", md)
        self.assertIn("已验证", md)


if __name__ == "__main__":
    unittest.main()
