import unittest
from sample_audio_probe import is_probe


class ProbeScopeTests(unittest.TestCase):
    def test_only_explicit_app_probe_is_sampled(self):
        self.assertTrue(is_probe('/sim/DarulIrfan.app/DarulIrfan --uitesting-audio-transport'))
        self.assertTrue(is_probe('"/sim with spaces/DarulIrfan.app/DarulIrfan" --uitesting-audio-transport'))
        for command in (
            '/sim/DarulIrfan.app/DarulIrfan --uitesting',
            '/other/App.app/App --uitesting-audio-transport',
            '/sim/DarulIrfan.app/DarulIrfan --uitesting-audio-transport-extra',
            '"unterminated',
            '',
        ):
            self.assertFalse(is_probe(command))


if __name__ == '__main__':
    unittest.main()
