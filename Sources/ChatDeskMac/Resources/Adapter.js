/* ChatDesk native adapter v0.2.0. Runs in a private WKContentWorld, main frame only.
   No fetch/XHR hooks, no private endpoints, no unsolicited clipboard access, no file-byte copies.
   Only a native user action can create/consume a native upload permit. */
(() => {
  'use strict';
  if (globalThis.ChatDeskAdapter) return;
  const fixture = location.protocol === 'file:' && /\/ClipboardFixture\.html$/.test(location.pathname);
  if (!fixture && !(location.protocol === 'https:' && ['chatgpt.com', 'chat.openai.com'].includes(location.hostname))) return;
  const documentID = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  let pending = null, lastClickedFileInput = null, draftTimer = null, disposed = false;
  const href = () => location.href;
  function composer() {
    return document.querySelector('#prompt-textarea[contenteditable="true"], textarea#prompt-textarea, textarea[data-testid="prompt-textarea"], [data-chatdesk-fixture-composer]');
  }
  function focusedComposer(c) {
    return !!c && (document.activeElement === c || c.contains(document.activeElement));
  }
  function temporary() {
    const params = new URLSearchParams(location.search);
    return params.get('temporary-chat') === 'true' || params.get('temporary') === 'true'
      || !!document.querySelector('[data-testid="temporary-chat-header"], [data-chatdesk-temporary="true"]');
  }
  function post(value) { try { globalThis.webkit?.messageHandlers?.chatdesk?.postMessage(value); } catch (_) {} }
  function draftText(c) { return c ? ('value' in c ? c.value : c.innerText) : ''; }
  function matchesAccept(input, file) {
    const accept = (input.getAttribute('accept') || '').trim().toLowerCase();
    if (!accept) return true;
    const extension = `.${String(file.extension || '').toLowerCase()}`;
    const mime = String(file.mime || '').toLowerCase();
    return accept.split(',').some(s => {
      const token = s.trim();
      return token === '*/*' || token === extension || token === mime
        || (token.endsWith('/*') && mime.startsWith(token.slice(0, -1)));
    });
  }
  function fileCandidates(c, files) {
    const form = c?.closest('form');
    const find = root => Array.from(root.querySelectorAll('input[type="file"]'))
      .filter(input => !input.disabled && (files.length <= 1 || input.multiple)
        && files.every(file => matchesAccept(input, file)));
    const inForm = form ? find(form) : [];
    return inForm.length ? inForm : find(document);
  }
  function context() {
    const c = composer();
    return {ok: true, href: href(), documentID, hasComposer: !!c, focused: focusedComposer(c), temporary: temporary()};
  }
  function prepareFiles(args) {
    const c = composer();
    if (!c) return {ok: false, error: 'ChatGPT\'s message field could not be found.'};
    if (args.requireFocus && !focusedComposer(c)) return {ok: false, error: 'Focus the message field before pasting attachments.'};
    if (typeof args.token !== 'string' || args.token.length > 80 || !Array.isArray(args.files)
        || args.files.length === 0 || args.files.length > 100) return {ok: false, error: 'Invalid local file operation.'};
    const candidates = fileCandidates(c, args.files);
    if (candidates.length !== 1) return {ok: false, error: candidates.length === 0
      ? 'No existing file control accepts the entire selection. No files were sent.'
      : 'Multiple file controls are possible. A safe automatic match cannot be determined.'};
    pending = {token: args.token, input: candidates[0], href: href(), documentID,
      preparedAt: Date.now(), triggered: false};
    lastClickedFileInput = null;
    return {...context(), ok: true, multiple: pending.input.multiple};
  }
  function validateFiles(args) {
    const valid = !!pending && pending.token === args.token && pending.href === href()
      && pending.documentID === documentID && pending.input.isConnected && !pending.input.disabled
      && pending.triggered && lastClickedFileInput === pending.input && Date.now() - pending.preparedAt <= 5000;
    return {...context(), ok: valid};
  }
  function triggerFiles(args) {
    if (!pending || pending.token !== args.token || pending.href !== href()
        || !pending.input.isConnected || Date.now() - pending.preparedAt > 5000) {
      pending = null; return {ok: false, error: 'The file page changed before handoff.'};
    }
    pending.triggered = true;
    // Ask the EXISTING web control to open its native picker. The WKUIDelegate may then
    // supply the already user-selected original URLs. No synthetic paste, new input, changed
    // accept/multiple attribute, manually assigned FileList, or fake upload-success event.
    pending.input.click();
    return {ok: true, requested: true}; // A request is NOT confirmation that files uploaded.
  }
  function cancelFiles() { pending = null; lastClickedFileInput = null; return {ok: true}; }
  function getDraft() {
    const text = draftText(composer());
    if (text.length > 65536) return {...context(), ok: false, error: 'The draft is too long for local storage. The text was not truncated.'};
    return {...context(), text};
  }
  function insertText(args) {
    const c = composer();
    if (!c || typeof args.text !== 'string' || args.text.length > 65536) return {ok: false, error: 'The text could not be inserted.'};
    if (args.onlyIfEmpty && draftText(c).length) return {ok: false, error: 'The field already contains text. Nothing was overwritten.'};
    c.focus();
    // execCommand is used solely for user-requested editing to preserve the editor's undo stack.
    // No DOM replacement fallback: that can desynchronise React/ProseMirror.
    const before = draftText(c);
    const inserted = document.execCommand('insertText', false, args.text);
    return {ok: inserted && draftText(c) !== before, error: inserted ? '' : 'The web editor did not accept the insertion. Copy the text manually.'};
  }
  function selectedText() {
    const active = document.activeElement;
    let text = '';
    if (active && ['INPUT', 'TEXTAREA'].includes(active.tagName)
        && Number.isInteger(active.selectionStart) && Number.isInteger(active.selectionEnd)) {
      text = String(active.value || '').slice(active.selectionStart, active.selectionEnd);
    } else {
      text = String(globalThis.getSelection?.()?.toString?.() || '');
    }
    if (!text) return {ok: false, error: 'No text is selected.'};
    if (text.length > 1_000_000) return {ok: false, error: 'The selection is too large to copy safely.'};
    return {ok: true, text};
  }
  function onCopy(event) {
    if (!event.isTrusted || !event.clipboardData) return;
    const selection = selectedText();
    if (!selection.ok) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    event.clipboardData.clearData();
    event.clipboardData.setData('text/plain', selection.text);
  }
  function copyElementAsPlainText(element) {
    const selection = globalThis.getSelection?.();
    if (!selection || !document.createRange || !document.execCommand) return false;
    const saved = [];
    for (let index = 0; index < selection.rangeCount; index += 1) saved.push(selection.getRangeAt(index).cloneRange());
    try {
      const range = document.createRange(); range.selectNodeContents(element);
      selection.removeAllRanges(); selection.addRange(range);
      return document.execCommand('copy');
    } catch (_) { return false; }
    finally {
      selection.removeAllRanges(); saved.forEach(range => selection.addRange(range));
    }
  }
  function applyReading(args) {
    let style = document.getElementById('chatdesk-reading-style');
    if (!style) { style = document.createElement('style'); style.id = 'chatdesk-reading-style'; document.head.append(style); }
    const width = Number(args.width) || 0;
    style.textContent = width >= 640 && width <= 1600
      ? `main [data-message-author-role] {max-width:${Math.round(width)}px !important;} main article .text-base {--thread-content-max-width:${Math.round(width)}px;}` : '';
    return {ok: true};
  }
  function onInput(event) {
    const c = composer();
    if (!c || !(event.target === c || c.contains(event.target))) return;
    clearTimeout(draftTimer);
    const atHref = href();
    draftTimer = setTimeout(() => {
      if (disposed || href() !== atHref || !c.isConnected) return;
      const text = draftText(c);
      if (text.length <= 65536) post({kind: 'draft', href: atHref, documentID, text, temporary: temporary()});
    }, 700);
  }
  function onClick(event) {
    const copyButton = event.isTrusted && event.target?.closest?.('[data-testid="copy-turn-action-button"]');
    if (copyButton) {
      const turn = copyButton.closest?.('[data-testid^="conversation-turn-"], article');
      const message = turn?.querySelector?.('[data-message-author-role]');
      const text = String(message?.innerText || '');
      if (text && copyElementAsPlainText(message)) {
        event.preventDefault(); event.stopImmediatePropagation();
        return;
      }
    }
    const input = event.target?.closest?.('input[type="file"]');
    if (input) lastClickedFileInput = input;
    // Conservative session-memory clearing on explicit account/workspace UI interaction.
    // This is NOT a reliable account identifier, so there is no automatic draft reinsertion.
    if (event.isTrusted && event.target?.closest?.('[data-testid="profile-button"], [data-testid="accounts-profile-button"], [data-testid="workspace-switcher"], a[href*="/auth/logout"]')) {
      cancelFiles(); post({kind: 'privacyBoundary'});
    }
  }
  function teardown() {
    disposed = true; clearTimeout(draftTimer); cancelFiles();
    document.removeEventListener('input', onInput, true);
    document.removeEventListener('click', onClick, true);
    document.removeEventListener('copy', onCopy, true);
    document.getElementById('chatdesk-reading-style')?.remove();
    delete globalThis.ChatDeskAdapter;
    return {ok: true};
  }
  document.addEventListener('input', onInput, true);
  document.addEventListener('click', onClick, true);
  document.addEventListener('copy', onCopy, true);
  globalThis.ChatDeskAdapter = Object.freeze({context, prepareFiles, triggerFiles, validateFiles,
    cancelFiles, getDraft, insertText, selectedText, applyReading, teardown});
})();
