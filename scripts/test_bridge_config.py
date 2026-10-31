"""Checks generated bridge configuration without Docker or real credentials."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import yaml


SOURCE = Path(__file__).resolve().parents[1] / 'apple/RelayKit/Sources/RelayKit/Resources/MessageHost/configure.py'
spec = importlib.util.spec_from_file_location('relay_bridge_config', SOURCE)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class BridgeConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        config.PRIVATE = Path(self.temp.name)

    def seed(self, name, network=None):
        folder = config.PRIVATE / name
        folder.mkdir()
        document = {
            'network': network or {},
            'homeserver': {},
            'appservice': {'as_token': 'generate', 'hs_token': 'generate'},
            'database': {},
            'bridge': {'permissions': {'*': 'relay'}, 'username_template': name + '_{{.}}'},
        }
        (folder / 'config.yaml').write_text(yaml.safe_dump(document))
        return folder / 'config.yaml'

    def test_messenger_uses_its_own_bot_and_facebook_mode(self):
        path = self.seed('messenger')
        config.bridge('messenger')
        result = yaml.safe_load(path.read_text())
        self.assertEqual(result['appservice']['id'], 'facebook')
        self.assertEqual(result['appservice']['bot']['username'], 'facebookbot')
        self.assertEqual(result['network']['mode'], 'facebook')
        self.assertEqual(result['appservice']['address'], 'http://messenger:29319')

    def test_telegram_consumes_private_api_credentials(self):
        path = self.seed('telegram', {'api_id': 12345, 'api_hash': 'tjyd5yge35lbodk1xwzw2jstp90k55qz'})
        name = 'telegram-credentials-00000000.json'
        secret = config.PRIVATE / name
        secret.write_text(json.dumps({'api_id': 67890, 'api_hash': 'a' * 32}))
        previous = config.os.environ.get('RELAY_TELEGRAM_CREDENTIAL_FILE')
        config.os.environ['RELAY_TELEGRAM_CREDENTIAL_FILE'] = name
        self.addCleanup(self.restore_environment, previous)
        config.bridge('telegram')
        result = yaml.safe_load(path.read_text())
        self.assertEqual(result['network']['api_id'], 67890)
        self.assertEqual(result['network']['api_hash'], 'a' * 32)
        self.assertFalse(secret.exists())

    @staticmethod
    def restore_environment(previous):
        if previous is None:
            config.os.environ.pop('RELAY_TELEGRAM_CREDENTIAL_FILE', None)
        else:
            config.os.environ['RELAY_TELEGRAM_CREDENTIAL_FILE'] = previous


if __name__ == '__main__':
    unittest.main()
