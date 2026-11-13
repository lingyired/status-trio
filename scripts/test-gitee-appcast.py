#!/usr/bin/env python3
import unittest
from importlib.machinery import SourceFileLoader

class AppcastTests(unittest.TestCase):
    def test_preserves_everything_except_verified_enclosure_url(self):
        helper = SourceFileLoader('gitee_appcast', 'scripts/generate-gitee-appcast.py').load_module()
        xml = '''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><description xml:lang="zh-Hans"><![CDATA[<enclosure url="fake"/>中文]]></description><sparkle:version>42</sparkle:version><enclosure url="https://github.com/o/r/releases/download/v1/a.dmg" sparkle:edSignature="signed" length="3"/><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion></item></channel></rss>'''.encode()
        old = 'https://github.com/o/r/releases/download/v1/a.dmg'
        new = 'https://gitee.com/o/r/attach_files/1/download/a.dmg'
        self.assertEqual(helper.derive(xml, {old: {'url': new, 'length': 3, 'signature': 'signed'}}), xml.replace(old.encode(), new.encode()))
        with self.assertRaises(ValueError):
            helper.derive(xml, {old: {'url': new, 'length': 4, 'signature': 'signed'}})
    def test_signed_feed_and_entities_fail_closed(self):
        helper = SourceFileLoader('gitee_appcast', 'scripts/generate-gitee-appcast.py').load_module()
        for xml in [b'<?sparkle edSignature="abc"?><rss/>', b'<!DOCTYPE rss [<!ENTITY x "xx">]><rss/>']:
            with self.assertRaises(ValueError):
                helper.derive(xml, {})

if __name__ == '__main__':
    unittest.main()
