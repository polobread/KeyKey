#!/usr/bin/env python3
"""Serve a local browser text field and record its real DOM input events."""

import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


PAGE = b'''<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>KeyKey browser typing fixture</title>
<style>
body { font: 22px sans-serif; margin: 48px; }
[hidden] { display: none !important; }
input, textarea, [contenteditable] {
  display: block; width: 740px; box-sizing: border-box; font: inherit;
}
textarea { height: 180px; }
[contenteditable] { min-height: 120px; border: 1px solid #888; padding: 4px; }
</style>
<label>Browser typing field</label>
<textarea id="textarea" aria-label="Browser typing field" hidden></textarea>
<input id="input" aria-label="Browser typing field" hidden>
<div id="contenteditable" contenteditable="true"
     aria-label="Browser typing field" hidden></div>
<script>
const params = new URLSearchParams(location.search);
const testCase = params.get('case') || 'default';
const field = params.get('field') || 'textarea';
const editor = document.getElementById(field);
if (!editor) throw new Error('Unknown editor field');
editor.hidden = false;
function value() {
  return 'value' in editor ? editor.value : editor.textContent;
}
function report(event) {
  fetch('/event', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({case: testCase, event,
                          value: value(),
                          focused: document.activeElement === editor})
  });
}
editor.addEventListener('focus', () => report('focus'));
editor.addEventListener('input', () => report('input'));
window.addEventListener('load', () => {
  editor.focus();
  report('ready');
});
</script>
</html>
'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/?') or self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(PAGE)))
            self.end_headers()
            self.wfile.write(PAGE)
            return
        self.send_error(404)

    def do_POST(self):
        if self.path != '/event':
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', '0'))
        if length < 1 or length > 4096:
            self.send_error(400)
            return
        try:
            event = json.loads(self.rfile.read(length))
            name = event['case']
            if not isinstance(name, str) or not re.fullmatch(r'[a-z0-9-]{1,80}', name):
                raise ValueError('Invalid case name')
            if not isinstance(event['value'], str) or len(event['value']) > 1000:
                raise ValueError('Invalid text')
            path = self.server.artifact_dir / f'{name}.jsonl'
            with path.open('a', encoding='utf-8') as output:
                output.write(json.dumps(event, ensure_ascii=False) + '\n')
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            self.send_error(400)
            return
        self.send_response(204)
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact_dir', type=Path)
    parser.add_argument('--port', type=int, default=18763)
    args = parser.parse_args()
    args.artifact_dir.mkdir(parents=True, exist_ok=True)
    server = HTTPServer(('127.0.0.1', args.port), Handler)
    server.artifact_dir = args.artifact_dir
    server.serve_forever()


if __name__ == '__main__':
    main()
