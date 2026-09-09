#!/usr/bin/env python3
"""Optional DEVELOPMENT test. Real browser file bytes; NOT Finder/WKWebView/ChatGPT.
Requires Python Playwright plus a browser. No dependency for the Mac application.
Usage: python3 scripts/test-browser-fixture.py --browser /path/to/chromium
"""
import argparse
import hashlib
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
MIMES = {'pdf': 'application/pdf', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'png': 'image/png', 'jpg': 'image/jpeg', 'txt': 'text/plain'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser', help='Existing Chromium executable; never installed automatically')
    args = parser.parse_args()
    checks = []
    def check(name, value):
        checks.append({'test': name, 'status': 'PASS' if value else 'FAIL'})
        assert value, name
    output = ROOT / 'test-results' / 'browser-fixture.json'
    output.parent.mkdir(exist_ok=True)
    report = {'scope': 'Chromium synthetic routed fixture; NOT native integration or live ChatGPT',
              'utc': datetime.now(timezone.utc).isoformat(), 'checks': checks}
    try:
        with sync_playwright() as p:
            kwargs = {'headless': True}
            if args.browser: kwargs['executable_path'] = args.browser
            browser = p.chromium.launch(**kwargs)
            report['browserVersion'] = browser.version
            page = browser.new_page()
            page_errors = []
            page.on('pageerror', lambda error: page_errors.append(str(error)))
            # Fulfil an in-memory fixture at an allowed adapter origin. EVERY request is
            # intercepted: this never contacts chatgpt.com, loads an account, or sends files.
            # File:// documents are blocked by this test host's managed browser policy.
            fixture_url = 'https://chatgpt.com/__chatdesk_synthetic_fixture__'
            fixture_html = (ROOT / 'Sources/ChatDeskMac/Resources/ClipboardFixture.html').read_text()
            def fixture_route(route):
                if route.request.url == fixture_url:
                    route.fulfill(status=200, content_type='text/html; charset=utf-8', body=fixture_html)
                else:
                    route.abort()
            page.route('**/*', fixture_route)
            page.goto(fixture_url)
            page.evaluate((ROOT / 'Sources/ChatDeskMac/Resources/Adapter.js').read_text())
            manifest = json.loads((ROOT / 'Fixtures/manifest.json').read_text())
            files = [ROOT / 'Fixtures/files' / item['name'] for item in manifest]
            descriptors = [{'extension': path.suffix[1:], 'mime': MIMES[path.suffix[1:]]} for path in files]
            sentinel = 'KEEP THIS TEXT AND UNICODE ÅÄÖ\nNo automatic submission.'
            page.locator('#prompt-textarea').fill(sentinel)
            context = page.evaluate('ChatDeskAdapter.context()')
            check('composer and document identity', context['hasComposer'] and context['focused'] and bool(context['documentID']))
            prepared = page.evaluate('(files)=>ChatDeskAdapter.prepareFiles({token:"native-permit-fixture",files,requireFocus:true})', descriptors)
            check('existing input accepts all six types', prepared['ok'] and prepared['multiple'])
            with page.expect_file_chooser() as request:
                page.evaluate('ChatDeskAdapter.triggerFiles({token:"native-permit-fixture"})')
            chooser = request.value
            check('real browser file chooser is multiple', chooser.is_multiple())
            check('clicked original control is validated', page.evaluate('ChatDeskAdapter.validateFiles({token:"native-permit-fixture"}).ok'))
            chooser.set_files([str(path) for path in files])
            page.wait_for_function('fixtureReport.pending===0 && fixtureReport.files.length===6')
            received = page.evaluate('fixtureReport')
            report['originalFiles'] = received
            check('all six original hashes and lengths received', all(item['matchesExpected'] is True for item in received['files']))
            check('original file order preserved', [x['name'] for x in received['files']] == [x['name'] for x in manifest])
            check('original typed text preserved', page.locator('#prompt-textarea').input_value() == sentinel)
            check('no form submission', received['submitted'] == 0)
            check('cancel invalidates permission', page.evaluate('ChatDeskAdapter.cancelFiles(); !ChatDeskAdapter.validateFiles({token:"native-permit-fixture"}).ok'))
            page.locator('#fixture-files').evaluate('(e)=>e.multiple=false')
            check('rejects multi-file use of single-file control', not page.evaluate('(files)=>ChatDeskAdapter.prepareFiles({token:"single",files})', descriptors)['ok'])
            page.locator('#fixture-files').evaluate('(e)=>{e.multiple=true;e.accept="image/*"}')
            check('rejects mixed list when web input accepts images only', not page.evaluate('(files)=>ChatDeskAdapter.prepareFiles({token:"images",files})', descriptors)['ok'])
            page.locator('#fixture-files').evaluate('(e)=>{e.accept="";let clone=e.cloneNode();clone.id="ambiguous";e.parentElement.append(clone)}')
            check('ambiguous file input rejected', not page.evaluate('(files)=>ChatDeskAdapter.prepareFiles({token:"ambiguous",files})', descriptors)['ok'])
            page.locator('#ambiguous').evaluate('(e)=>e.remove()')
            page.locator('#prompt-textarea').fill('')
            check('explicit insert edits textarea', page.evaluate('ChatDeskAdapter.insertText({text:"Explicit text",onlyIfEmpty:true}).ok'))
            check('restore cannot overwrite nonempty textarea', not page.evaluate('ChatDeskAdapter.insertText({text:"wrong",onlyIfEmpty:true}).ok'))
            check('safe insert preserves prior text', page.locator('#prompt-textarea').input_value() == 'Explicit text')
            page.evaluate('(files)=>ChatDeskAdapter.prepareFiles({token:"route",files})', descriptors)
            page.evaluate('location.hash="changed-route"')
            check('route change invalidates pending selection', not page.evaluate('ChatDeskAdapter.triggerFiles({token:"route"}).ok'))
            with tempfile.TemporaryDirectory(prefix='chatdesk-fixture-') as temp:
                same_name_paths = []
                for folder, content in [('one', b'first original'), ('two', b'different original')]:
                    path = Path(temp) / folder / 'same name.txt'; path.parent.mkdir(); path.write_bytes(content); same_name_paths.append(path)
                page.locator('#reset').click()
                page.locator('#fixture-files').set_input_files([str(path) for path in same_name_paths])
                page.wait_for_function('fixtureReport.pending===0 && fixtureReport.files.length===2')
                duplicates = page.evaluate('fixtureReport')
                expected = [hashlib.sha256(path.read_bytes()).hexdigest() for path in same_name_paths]
                check('same basename different directories retain both originals', [item['sha256'] for item in duplicates['files']] == expected)
            check('no browser JavaScript exception', not page_errors)
            report['limitations'] = ['Synthetic document fulfilled in memory; all network requests intercepted.', 'Browser automation provided files to a real input.',
              'No macOS NSPasteboard or WKUIDelegate ran.', 'No account login or ChatGPT upload ran.']
            report['status'] = 'PASS'; browser.close()
    except Exception as error:
        report['status'] = 'BLOCKED' if 'ERR_BLOCKED_BY_ADMINISTRATOR' in str(error) else 'FAIL'
        report['error'] = str(error)
        raise
    finally:
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f"PASS: {len(checks)} local Chromium checks. NOT native/live verification.")

if __name__ == '__main__': main()
