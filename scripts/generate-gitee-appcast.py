#!/usr/bin/env python3
"""Preserve XML bytes; replace only verified enclosure URLs."""
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
from xml.parsers import expat
from xml.sax.saxutils import escape
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

def derive(xml, mappings):
    parser = expat.ParserCreate(namespace_separator='|')
    replacements, seen, root = [], set(), []
    def reject(*args):
        raise ValueError('Signed feed / DTD / entity requires a supported signing pipeline')
    parser.ProcessingInstructionHandler = reject
    parser.StartDoctypeDeclHandler = reject
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = reject
    def start(name, attrs):
        if not root:
            if name != 'rss':
                raise ValueError('Not an RSS appcast')
            root.append(name)
        if name != 'enclosure' or attrs.get('url') not in mappings:
            return
        original = attrs['url']
        mirror = mappings[original]
        if str(mirror['length']) != attrs.get('length') or mirror['signature'] != attrs.get(SPARKLE + '|edSignature'):
            raise ValueError('Enclosure identity mismatch')
        if urlsplit(mirror['url']).scheme != 'https':
            raise ValueError('Mirror URL must be HTTPS')
        pos = parser.CurrentByteIndex
        match = re.match(br'''<(?:"[^"]*"|'[^']*'|[^'">])*>''', xml[pos:])
        if not match:
            raise ValueError('Unsupported enclosure encoding')
        tag = match.group()
        attr = re.search(br'''[ ]url[ ]*=[ ]*(["'])(.*?)\1''', tag, re.S)
        if not attr:
            raise ValueError('Missing URL attribute')
        value = escape(mirror['url'], {'"': '&quot;', "'": '&apos;'}).encode('utf-8')
        replacements.append((pos + attr.start(2), pos + attr.end(2), value))
        seen.add(original)
    parser.StartElementHandler = start
    parser.Parse(xml, True)
    if not root or seen != set(mappings):
        raise ValueError('Verified version missing from authoritative appcast')
    for begin, end, value in reversed(replacements):
        xml = xml[:begin] + value + xml[end:]
    expat.ParserCreate().Parse(xml, True)
    return xml

if __name__ == '__main__':
    source, mapping, output = sys.argv[1:]
    Path(output).write_bytes(derive(Path(source).read_bytes(), json.loads(Path(mapping).read_text())))
