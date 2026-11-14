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
    def test_prunes_unmirrored_items_and_leaves_no_github_urls(self):
        helper = SourceFileLoader('gitee_appcast', 'scripts/generate-gitee-appcast.py').load_module()
        xml = '''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><link>https://github.com/o/r</link><item><sparkle:version>41</sparkle:version><enclosure url="https://github.com/o/r/releases/download/v1.0/a.dmg" length="3" sparkle:edSignature="old"/></item><item><sparkle:version>42</sparkle:version><description><![CDATA[<a href="https://github.com/o/r/blob/main/privacy.md">privacy</a>]]></description><enclosure url="https://github.com/o/r/releases/download/v1.1/b.dmg" length="3" sparkle:edSignature="signed"/></item></channel></rss>'''.encode()
        json_map = {'https://github.com/o/r/releases/download/v1.1/b.dmg': {'url': 'https://gitee.com/o/r/attach_files/2/download/b.dmg', 'length': 3, 'signature': 'signed'}}
        result = helper.derive(xml, json_map, 'o/r')
        self.assertNotIn(b'github.com', result)
        self.assertNotIn(b'v1.0', result)
        self.assertEqual(result.count(b'<item>'), 1)
        self.assertIn(b'https://gitee.com/o/r/blob/main/privacy.md', result)
        self.assertIn(b'https://gitee.com/o/r/attach_files/2/download/b.dmg', result)
        self.assertIn(b'edSignature="signed"', result)

    def test_rejects_non_gitee_mirror_url(self):
        helper = SourceFileLoader('gitee_appcast', 'scripts/generate-gitee-appcast.py').load_module()
        xml = '''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://github.com/o/r/a.dmg" length="3" sparkle:edSignature="s"/></item></channel></rss>'''.encode()
        with self.assertRaises(ValueError):
            helper.derive(xml, {'https://github.com/o/r/a.dmg': {'url': 'https://evil.test/a.dmg', 'length': 3, 'signature': 's'}}, 'o/r')

    def test_signed_feed_and_entities_fail_closed(self):
        helper = SourceFileLoader('gitee_appcast', 'scripts/generate-gitee-appcast.py').load_module()
        for xml in [b'<?sparkle edSignature="abc"?><rss/>', b'<!DOCTYPE rss [<!ENTITY x "xx">]><rss/>']:
            with self.assertRaises(ValueError):
                helper.derive(xml, {})

if __name__ == '__main__':
    unittest.main()
