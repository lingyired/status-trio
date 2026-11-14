#!/usr/bin/env python3
"""Derive a Gitee-only feed with no GitHub URLs.

Only versions actually mirrored to Gitee are kept; unmapped historical items
are omitted. Release-note links are rewritten to the Gitee repository. The
authoritative XML bytes, CDATA, namespaces, lengths and Sparkle signatures are
otherwise preserved. Unknown feed signatures, DTDs and entities fail closed.
"""
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
from xml.parsers import expat
from xml.sax.saxutils import escape

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

def derive(xml, mappings, mirror_repo=None):
    parser = expat.ParserCreate(namespace_separator='|')
    replacements = []
    seen = set()
    root = []
    items = []
    current_item = None

    def reject(*args):
        raise ValueError('Signed feed / DTD / entity requires a supported signing pipeline')

    parser.ProcessingInstructionHandler = reject
    parser.StartDoctypeDeclHandler = reject
    parser.EntityDeclHandler = reject
    parser.ExternalEntityRefHandler = reject

    def start(name, attrs):
        nonlocal current_item
        if not root:
            if name != 'rss':
                raise ValueError('Not an RSS appcast')
            root.append(name)
        if name == 'item':
            if current_item is not None:
                raise ValueError('Nested item is not supported')
            current_item = {'start': parser.CurrentByteIndex, 'mapped': False}
            return
        if name != 'enclosure' or attrs.get('url') not in mappings:
            return
        if current_item is None:
            raise ValueError('Enclosure outside item')
        current_item['mapped'] = True
        original = attrs['url']
        mirror = mappings[original]
        if str(mirror['length']) != attrs.get('length') or mirror['signature'] != attrs.get(SPARKLE + '|edSignature'):
            raise ValueError('Enclosure identity mismatch')
        if urlsplit(mirror['url']).scheme != 'https' or urlsplit(mirror['url']).hostname != 'gitee.com':
            raise ValueError('Mirror URL must be a Gitee HTTPS attachment')
        pos = parser.CurrentByteIndex
        match = re.match(br'''<(?:"[^"]*"|'[^']*'|[^'">])*>''', xml[pos:])
        if not match:
            raise ValueError('Unsupported enclosure encoding')
        attr = re.search(br'''[ ]url[ ]*=[ ]*(["'])(.*?)\1''', match.group(), re.S)
        if not attr:
            raise ValueError('Missing URL attribute')
        value = escape(mirror['url'], {'"': '&quot;', "'": '&apos;'}).encode('utf-8')
        replacements.append((pos + attr.start(2), pos + attr.end(2), value))
        seen.add(original)

    def end(name):
        nonlocal current_item
        if name != 'item':
            return
        if current_item is None:
            raise ValueError('Unbalanced item')
        close = xml.index(b'>', parser.CurrentByteIndex) + 1
        items.append((current_item['start'], close, current_item['mapped']))
        current_item = None

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.Parse(xml, True)
    if not root or seen != set(mappings):
        raise ValueError('Verified version missing from authoritative appcast')

    # Apply enclosure replacements and whole-item removals in one descending
    # pass so every byte offset still refers to the original document.
    edits = replacements + [(begin, finish, b'') for begin, finish, mapped in items if not mapped]
    for begin, finish, value in sorted(edits, key=lambda edit: edit[0], reverse=True):
        xml = xml[:begin] + value + xml[finish:]

    if mirror_repo:
        xml = xml.replace(
            ('https://raw.githubusercontent.com/' + mirror_repo).encode(),
            ('https://gitee.com/' + mirror_repo + '/raw').encode(),
        )
        xml = xml.replace(
            ('https://github.com/' + mirror_repo).encode(),
            ('https://gitee.com/' + mirror_repo).encode(),
        )
    if b'github.com' in xml or b'githubusercontent.com' in xml:
        raise ValueError('Gitee feed still contains a GitHub URL')
    expat.ParserCreate().Parse(xml, True)
    return xml

if __name__ == '__main__':
    source, mapping, output = sys.argv[1:4]
    repo = sys.argv[4] if len(sys.argv) > 4 else None
    Path(output).write_bytes(derive(Path(source).read_bytes(), json.loads(Path(mapping).read_text()), repo))
