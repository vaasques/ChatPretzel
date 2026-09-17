/* ChatDesk native adapter v0.3.0. Runs in a private WKContentWorld, main frame only.
   No fetch/XHR hooks, no private endpoints, no unsolicited clipboard access, no file-byte copies.
   Only a native user action can create/consume a native upload permit. */
(() => {
  'use strict';
  if (globalThis.ChatDeskAdapter) return;
  const fixture = location.protocol === 'file:' && /\/ClipboardFixture\.html$/.test(location.pathname);
  if (!fixture && !(location.protocol === 'https:' && ['chatgpt.com', 'chat.openai.com'].includes(location.hostname))) return;
  const documentID = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  let pending = null, superUpload = null, lastClickedFileInput = null, draftTimer = null, disposed = false;
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
  function normalizedMessageText(value) {
    return String(value || '').normalize('NFC')
      .replace(/[\u200B-\u200D\uFEFF]/g, '')
      .replace(/\u00A0/g, ' ')
      .replace(/\r\n?/g, '\n')
      .replace(/[\t\f\v ]+/g, ' ')
      .replace(/ *\n+ */g, '\n')
      .trim();
  }
  // Visibility is intentional here: hidden stop/progress controls and virtualized
  // cards must never be treated as evidence of a live upload or response.
  function visible(node) {
    if (!node || node.hidden || node.getAttribute?.('aria-hidden') === 'true') return false;
    const hiddenAncestor = node.closest?.('[hidden], [aria-hidden="true"]');
    if (hiddenAncestor && hiddenAncestor !== node) return false;
    const style = globalThis.getComputedStyle?.(node);
    if (style && (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0')) return false;
    if (typeof node.getClientRects === 'function' && !node.getClientRects().length) return false;
    return node.isConnected !== false;
  }
  function basename(value) {
    return String(value || '').replace(/^.*[\\/]/, '');
  }
  function textHash(value) {
    let result = 2166136261;
    for (let index = 0; index < value.length; index++) {
      result ^= value.charCodeAt(index);
      result = Math.imul(result, 16777619);
    }
    return (result >>> 0).toString(36);
  }
  function messageSignature(node) {
    if (!node) return '';
    const turn = node.closest?.('[data-testid^="conversation-turn-"]');
    const identifier = turn?.getAttribute?.('data-testid')
      || node.getAttribute?.('data-message-id') || node.id || '';
    const value = normalizedMessageText(node.innerText || node.textContent || '');
    return value || identifier ? `${identifier}|${value.length}|${textHash(value)}` : '';
  }
  function latestAssistantSignature() {
    const messages = Array.from(document.querySelectorAll('[data-message-author-role="assistant"]'));
    if (messages.length) return messageSignature(messages[messages.length - 1]);
    const actions = Array.from(document.querySelectorAll('[data-testid="copy-turn-action-button"]'));
    const last = actions[actions.length - 1];
    return messageSignature(last?.closest?.('[data-testid^="conversation-turn-"], article') || last);
  }
  function latestUserSignature() {
    const messages = Array.from(document.querySelectorAll('[data-message-author-role="user"]'));
    return messages.length ? messageSignature(messages[messages.length - 1]) : '';
  }
  function attachmentName(node) {
    if (!node) return '';
    const direct = ['data-file-name', 'data-filename', 'data-name', 'title', 'aria-label']
      .map(attribute => node.getAttribute?.(attribute) || '').find(Boolean) || '';
    if (direct) {
      // aria-labels commonly contain an action prefix; prefer an exact basename
      // attribute/title, and only use the last phrase for the accessible fallback.
      if (node.getAttribute?.('data-file-name') || node.getAttribute?.('data-filename') || node.getAttribute?.('title')) return normalizedMessageText(basename(direct));
      const match = direct.match(/(?:file|attachment)[:\s-]+(.+?)(?:\s+(?:remove|delete)\b)?$/i);
      return normalizedMessageText(basename(match ? match[1] : direct));
    }
    const image = node.querySelector?.('img[alt]');
    if (image?.getAttribute?.('alt')) return normalizedMessageText(basename(image.getAttribute('alt')));
    const child = Array.from(node.querySelectorAll?.('[data-file-name], [data-filename], [title], img[alt]') || [])
      .map(candidate => candidate.getAttribute?.('data-file-name') || candidate.getAttribute?.('data-filename')
        || candidate.getAttribute?.('title') || candidate.getAttribute?.('alt') || '').find(Boolean);
    if (child) return normalizedMessageText(basename(child));
    // Text fallback is allowed only for an explicit attachment card, never for
    // arbitrary conversation/body nodes.
    if (node.getAttribute?.('data-testid')?.includes('attachment') || node.hasAttribute?.('data-chatdesk-attachment')) {
      return normalizedMessageText(basename(node.innerText || node.textContent || ''));
    }
    return '';
  }
  function attachmentCards(root = document) {
    const selectors = '[data-chatdesk-attachment], [data-testid="file-attachment"], [data-testid*="attachment"], [data-testid="file-upload"], [data-testid="file-card"], [data-file-name], [data-filename]';
    const seen = new Set();
    const explicit = Array.from(root.querySelectorAll?.(selectors) || []).filter(node => !seen.has(node) && seen.add(node))
      .filter(node => node.closest?.('[data-chatdesk-attachment], [data-testid="file-attachment"]') === node || !node.closest?.('[data-chatdesk-attachment], [data-testid="file-attachment"]'))
      .filter(visible)
      .map(node => ({node, name: attachmentName(node)})).filter(card => !!card.name);
    // Some file/image cards have a full filename only in a tooltip or alt text.
    // Accept that evidence only inside a remove-capable card or a sent file link;
    // arbitrary prose mentioning a filename is not an attachment.
    const expected = [...(superUpload?.expectedFiles || []), ...(superUpload?.boundFileNames || [])];
    // ChatGPT's current composer exposes the filename through its localized
    // remove button, without a file-card test id or a filename tooltip.
    for (const remove of Array.from(root.querySelectorAll?.('button[aria-label], [role="button"][aria-label]') || [])) {
      if (!visible(remove)) continue;
      const match = String(remove.getAttribute('aria-label') || '').match(/^(?:remove|delete|ta bort|radera)\s+(?:file|attachment|fil|bilaga)\s*(?:\d+)?\s*:\s*(.+)$/i);
      if (!match) continue;
      const name = normalizedMessageText(basename(match[1]));
      let node = remove.parentElement || remove;
      for (let depth = 0, parent = node; parent && parent !== root && depth < 4; depth++, parent = parent.parentElement) {
        if (parent.matches?.('form, article, [data-testid^="conversation-turn-"]')) break;
        const controls = Array.from(parent.querySelectorAll?.('button, [role="button"]') || []);
        if (controls.some(control => control !== remove && normalizedMessageText(control.getAttribute?.('aria-label') || control.textContent || '').split('\n')[0] === name)) {
          node = parent; break;
        }
      }
      if (!explicit.some(card => card.node === node || card.node.contains?.(remove))) explicit.push({node, name});
    }
    for (const label of Array.from(root.querySelectorAll?.('[title], img[alt]') || [])) {
      if (!visible(label) || composer()?.contains(label)) continue;
      const name = normalizedMessageText(basename(label.getAttribute('title') || label.getAttribute('alt') || ''));
      if (!expected.includes(name) || explicit.some(card => card.node === label || card.node.contains?.(label))) continue;
      let node = label, selected = null;
      for (let depth = 0; node && node !== root && depth < 4; depth++, node = node.parentElement) {
        if (node.matches?.('form, article, [data-testid^="conversation-turn-"]')) break;
        if (cardRemoveControl({node}) || node.matches?.('a[href]')) { selected = node; break; }
      }
      if (selected && !explicit.some(card => card.node === selected)) explicit.push({node: selected, name});
    }
    // Sent attachments are interactive filename buttons/links; their remove
    // controls disappear after sending. Stay scoped to the supplied user turn.
    if (root.matches?.('[data-testid^="conversation-turn-"], article')) {
      for (const control of Array.from(root.querySelectorAll?.('button, [role="button"], a[href], [role="group"][aria-label]') || [])) {
        if (!visible(control)) continue;
        const label = normalizedMessageText(control.getAttribute?.('aria-label') || control.getAttribute?.('title') || control.textContent || '').split('\n')[0];
        const imageLabel = label.match(/^(?:open image(?: \d+ of \d+)?|öppna bild(?: \d+ av \d+)?):\s*(.+)$/i);
        const name = imageLabel ? imageLabel[1] : label;
        if (!expected.includes(name) || explicit.some(card => card.node === control || card.node.contains?.(control) || control.contains?.(card.node))) continue;
        explicit.push({node: control, name});
      }
      // Table/file previews in a sent user turn do not expose filename
      // attributes. Accept only a uniquely matching title stem with the
      // preview's download/expand controls; arbitrary prose is never evidence.
      const stem = value => normalizedMessageText(basename(value)).replace(/\.(?:csv|tsv|xlsx?|ods)$/i, '').replace(/[\s_-]+/g, ' ').toLowerCase();
      const tableNames = [...new Set(superUpload?.boundFileNames || superUpload?.expectedFiles || [])];
      const tableSelector = '[role="table"], [role="grid"], table';
      for (const preview of Array.from(root.querySelectorAll?.(tableSelector) || [])) {
        // ChatGPT's canvas spreadsheet exposes a non-rendered semantic table
        // as canvas fallback content. Bind evidence to the visible canvas,
        // never to an arbitrary hidden table elsewhere in the turn.
        const canvas = preview.closest?.('canvas');
        if (!visible(preview) && !(canvas && visible(canvas))) continue;
        // Scroll/viewport wrappers can put the header several levels above the
        // table. The turn boundary, unique table and exact title still bind it.
        for (let parent = preview.parentElement, depth = 0; parent && parent !== root && depth < 12; parent = parent.parentElement, depth++) {
          if (parent.querySelectorAll?.(tableSelector).length !== 1) break;
          const title = parent.getAttribute?.('aria-label') || parent.getAttribute?.('title')
            || String(parent.innerText || '').split('\n').map(line => line.trim()).find(Boolean) || '';
          const matches = tableNames.filter(name => /\.(?:csv|tsv|xlsx?|ods)$/i.test(name) && stem(name) === stem(title));
          const controls = Array.from(parent.querySelectorAll?.('button, [role="button"]') || []).filter(visible);
          if (matches.length === 1 && controls.length >= 2) {
            if (!explicit.some(card => card.node === parent || card.node.contains?.(preview))) explicit.push({node: parent, name: matches[0]});
            break;
          }
        }
      }
    }
    return explicit;
  }
  function composerAttachmentCards(c) {
    const form = c?.closest?.('form');
    const local = form ? attachmentCards(form) : [];
    if (local.length) return local;
    // Some layouts portal the composer cards into a nearby container. Walk only
    // a few ancestors and reject every conversation turn/article to avoid history.
    let scope = c;
    for (let depth = 0; depth < 3 && scope; depth += 1) {
      scope = scope.parentElement || scope.parentNode;
      if (!scope || scope.matches?.('[data-testid^="conversation-turn-"], article')) continue;
      const cards = attachmentCards(scope).filter(card => !card.node.closest?.('[data-testid^="conversation-turn-"], article'));
      if (cards.length) return cards;
    }
    // A portal may be outside the form. Only live remove-capable cards outside
    // every conversation turn are eligible here; history cannot satisfy this.
    return attachmentCards(document).filter(card => cardRemoveControl(card)
      && !card.node.closest?.('[data-testid^="conversation-turn-"], article'));
  }
  function multiset(names) {
    const map = new Map();
    names.forEach(name => map.set(name, (map.get(name) || 0) + 1));
    return map;
  }
  function expectedNewCards() {
    if (!superUpload?.expectedFiles) return [];
    const current = composerAttachmentCards(composer());
    const baseline = multiset(superUpload.attachmentBaseline || []);
    const added = [];
    current.forEach(card => {
      const count = baseline.get(card.name) || 0;
      if (count) baseline.set(card.name, count - 1); else added.push(card);
    });
    return added;
  }
  function failedCard(card) {
    const node = card.node;
    const status = `${node.getAttribute?.('data-upload-status') || ''} ${node.getAttribute?.('data-state') || ''}`.toLowerCase();
    return /fail|error|invalid/.test(status) || !!node.querySelector?.('[role="alert"], [data-testid*="error"], [data-upload-error]');
  }
  function cardRemoveControl(card) {
    return Array.from(card.node.querySelectorAll?.('button, [role="button"]') || [])
      .filter(visible).find(control => {
        const label = `${control.getAttribute?.('aria-label') || ''} ${control.getAttribute?.('title') || ''} ${control.getAttribute?.('data-testid') || ''}`.toLowerCase();
        return /remove|delete|ta bort|radera/.test(label);
      }) || null;
  }
  function cardsMatchNames(cards, names) {
    const available = multiset(cards.map(card => card.name));
    return names.every(name => {
      const count = available.get(name) || 0;
      if (!count) return false;
      available.set(name, count - 1); return true;
    }) && cards.length === names.length;
  }
  function bindAttachmentNames(cards, names) {
    if (cards.length !== names.length) return null;
    const remaining = cards.map(card => card.name), bound = names.map(() => null);
    // Reserve exact names first, so report(1).pdf cannot be stolen as an alias
    // for a distinct report.pdf selected alongside it.
    names.forEach((name, index) => {
      const exact = remaining.indexOf(name);
      if (exact >= 0) { bound[index] = remaining[exact]; remaining[exact] = null; }
    });
    for (let index = 0; index < names.length; index++) {
      if (bound[index] !== null) continue;
      const matches = remaining.map((name, position) => ({name, position})).filter(({name}) => name
        && name.replace(/\s*\(\d+\)(?=\.[^.]+$|$)/, '') === names[index]);
      if (matches.length !== 1) return null;
      bound[index] = matches[0].name; remaining[matches[0].position] = null;
    }
    return bound;
  }
  function draftMatchesExpected(c) {
    return !!superUpload?.expectedDraft
      && normalizedMessageText(draftText(c)) === superUpload.expectedDraftKey;
  }
  function lastUserMatchesExpected() {
    if (!superUpload?.expectedDraftKey) return false;
    const messages = Array.from(document.querySelectorAll('[data-message-author-role="user"]'));
    const turns = messages.length ? messages.slice(-1)
      : Array.from(document.querySelectorAll('[data-testid^="conversation-turn-"]')).slice(-4);
    return turns.some(node => {
      const value = normalizedMessageText(node.innerText || node.textContent || '');
      // Some ChatGPT layouts include attachment labels before the textual message in the
      // same user turn, while others expose only the text node.
      return value === superUpload.expectedDraftKey || value.endsWith(`\n${superUpload.expectedDraftKey}`);
    });
  }
  function moveCaretToEnd(c) {
    if ('value' in c && typeof c.setSelectionRange === 'function') {
      const end = String(c.value || '').length;
      c.setSelectionRange(end, end);
      return true;
    }
    const selection = globalThis.getSelection?.();
    if (!selection || !document.createRange) return false;
    const range = document.createRange();
    range.selectNodeContents(c); range.collapse(false);
    selection.removeAllRanges(); selection.addRange(range);
    return true;
  }
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
  function multipleFileControls(c) {
    const form = c?.closest('form');
    const find = root => Array.from(root.querySelectorAll('input[type="file"]'))
      .filter(input => !input.disabled && input.multiple && input.isConnected);
    const inForm = form ? find(form) : [];
    return inForm.length ? inForm : find(document);
  }
  function chooseSuperUploadInput(c, types) {
    const scored = multipleFileControls(c).map(input => {
      const accepted = types.map(file => matchesAccept(input, file));
      const score = accepted.reduce((sum, ok, index) => sum + (ok ? Math.max(1, Number(types[index]?.count) || 1) : 0), 0);
      return {input, accepted, score};
    });
    const maximum = Math.max(0, ...scored.map(item => item.score));
    const winners = scored.filter(item => item.score === maximum);
    if (!maximum) return {ok: false, unsupportedAll: true,
      error: 'The current ChatGPT file control does not accept any of these file types.'};
    if (winners.length !== 1) return {ok: false, error: 'Multiple file controls are possible. A safe Super Upload match cannot be determined.'};
    return {ok: true, ...winners[0]};
  }
  function messageCounts() {
    return {
      userMessages: document.querySelectorAll('[data-message-author-role="user"]').length,
      assistantMessages: document.querySelectorAll('[data-message-author-role="assistant"]').length
    };
  }
  function languageSample() {
    const messages = Array.from(document.querySelectorAll('[data-message-author-role="user"]')).slice(-4);
    return messages.map(node => {
      // File cards and table previews often contribute their title/filename to
      // innerText.  Prefer the actual message text nodes and strip only known
      // preview/card subtrees; never use arbitrary page prose as a sample.
      const copy = node.cloneNode?.(true);
      if (copy?.querySelectorAll) {
        copy.querySelectorAll('[data-chatdesk-attachment], [data-testid*="attachment"], [data-testid*="file"], [data-file-name], [data-filename], [role="table"], table').forEach(child => child.remove?.());
        return String(copy.innerText || copy.textContent || '');
      }
      return String(node.innerText || '');
    }).join('\n').slice(-8000);
  }
  function sendButton(c) {
    const form = c?.closest('form');
    if (!form) return null;
    const preferred = form.querySelector('button[data-testid="send-button"]');
    if (visible(preferred)) return preferred;
    const candidates = Array.from(form.querySelectorAll('button[type="submit"]'))
      .filter(button => visible(button) && button.dataset?.testid !== 'stop-button');
    return candidates.length === 1 ? candidates[0] : null;
  }
  function uploadInProgress(c) {
    const form = c?.closest('form');
    const selector = '[role="progressbar"], [data-state="uploading"], [data-testid*="upload-progress"], [data-testid*="upload"][aria-busy="true"]';
    return !!(form?.matches?.(selector) || form?.querySelector(selector) || document.querySelector(selector));
  }
  function generationInProgress() {
    if (Array.from(document.querySelectorAll('[data-testid="stop-button"]')).some(visible)) return true;
    return Array.from(document.querySelectorAll('button[aria-label]')).filter(visible).some(button => {
      const label = String(button.getAttribute('aria-label') || '').toLowerCase();
      return label.includes('stop generating') || label.includes('stop response')
        || label.includes('stoppa generering') || label.includes('avbryt svar');
    });
  }
  function idleResponseControl(c) {
    const form = c?.closest('form');
    if (!form) return false;
    if (visible(form.querySelector('[data-testid="voice-mode-button"], [data-chatdesk-idle-control]'))) return true;
    return Array.from(form.querySelectorAll('button[aria-label]')).filter(visible).some(button => {
      const label = String(button.getAttribute('aria-label') || '').toLowerCase();
      return label.includes('voice mode') || label.includes('röstläge');
    });
  }
  function visibleAlertText() {
    const cards = composerAttachmentCards(composer());
    return Array.from(document.querySelectorAll('[role="alert"]')).filter(visible)
      .filter(node => !cards.some(card => card.node === node || card.node.contains?.(node)))
      .filter(node => !node.closest?.('[data-chatdesk-attachment], [data-testid="file-attachment"], [data-testid*="attachment"], [data-file-name]')).map(node => String(node.innerText || node.textContent || '').trim())
      .filter(text => /something went wrong|network error|server error|failed to (?:upload|send|generate)|(?:upload|file|rate|usage) limit|quota exceeded|too many (?:files|requests)|unsupported file|file type.*not supported|could not (?:upload|send|generate)|upload.*(?:failed|error)|något gick fel|nätverksfel|kunde inte (?:ladda|skicka|generera)|för många (?:filer|förfrågningar)|uppladdning.*(?:misslyck|gräns)/i.test(text))
      .slice(-3).join('\n').slice(0, 2000);
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
    let candidates = [];
    if (typeof args.superUploadToken === 'string' && superUpload?.token === args.superUploadToken
        && superUpload.documentID === documentID) {
      if (superUpload.input?.isConnected && !superUpload.input.disabled && superUpload.input.multiple
          && args.files.every(file => matchesAccept(superUpload.input, file))) {
        candidates = [superUpload.input];
      } else {
        candidates = fileCandidates(c, args.files);
        if (candidates.length === 1) superUpload.input = candidates[0];
      }
    } else {
      candidates = fileCandidates(c, args.files);
    }
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
  function removePreparedSuffix(session) {
    if (!session?.appendedSuffix || session.appendedDocumentID !== documentID
        || session.appendedHref !== href()) return false;
    const c = composer();
    const current = draftText(c);
    if (!c) return false;
    if (!current.endsWith(session.appendedSuffix) && typeof c.setSelectionRange === 'function') return false;
    const suffixStart = current.length - session.appendedSuffix.length;
    if (typeof c.setSelectionRange === 'function') {
      c.focus(); c.setSelectionRange(suffixStart, current.length);
      if (document.execCommand?.('delete')) return true;
      if (typeof c.setRangeText === 'function') { c.setRangeText('', suffixStart, current.length, 'end'); return true; }
      // Test/fallback textarea controls have no native delete command. The
      // range check above guarantees that only the exact app suffix is removed.
      c.value = current.slice(0, suffixStart);
      return true;
    }
    // Contenteditable composers need a DOM range so React/ProseMirror sees a
    // normal editor deletion. Walk text nodes to select only the exact suffix.
    // Paragraph boundaries can make innerText and textContent differ. If the
    // draft is still byte-for-byte the prepared draft, replace it through the
    // editor command with the original prefix; this cannot erase user edits.
    if (session.appendedDraft && current === session.appendedDraft && document.execCommand && globalThis.getSelection) {
      const selection = globalThis.getSelection(); const range = document.createRange?.();
      if (range) { range.selectNodeContents(c); selection.removeAllRanges(); selection.addRange(range); return !!document.execCommand('insertText', false, session.appendedPrefix || ''); }
    }
    const rootText = String(c.textContent || '');
    if (!rootText.endsWith(session.appendedSuffix) || !document.createRange || !globalThis.getSelection) return false;
    const start = rootText.length - session.appendedSuffix.length;
    const textNodes = [];
    const collect = node => {
      if (node?.nodeType === 3) textNodes.push(node);
      else Array.from(node?.childNodes || []).forEach(collect);
    };
    collect(c);
    let offset = 0, startPoint = null, endPoint = null;
    for (const node of textNodes) {
      const next = offset + String(node.nodeValue || '').length;
      if (!startPoint && start >= offset && start <= next) startPoint = [node, start - offset];
      if (!endPoint && rootText.length >= offset && rootText.length <= next) endPoint = [node, rootText.length - offset];
      offset = next;
    }
    if (!startPoint || !endPoint) return false;
    const range = document.createRange();
    range.setStart?.(startPoint[0], startPoint[1]); range.setEnd?.(endPoint[0], endPoint[1]);
    const selection = globalThis.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    if (document.execCommand?.('delete')) return true;
    if (range.deleteContents) { range.deleteContents(); return true; }
    return false;
  }
  function beginSuperUpload(args) {
    const c = composer();
    if (!c) return {ok: false, error: 'ChatGPT\'s message field could not be found.'};
    if (args.requireFocus && !focusedComposer(c)) return {ok: false, error: 'Focus the message field before pasting attachments.'};
    const types = Array.isArray(args.types) ? args.types : args.files;
    if (superUpload || typeof args.token !== 'string' || args.token.length > 80 || !Array.isArray(types)
        || types.length === 0) return {ok: false, error: 'Invalid or already active Super Upload operation.'};
    const selected = chooseSuperUploadInput(c, types);
    if (!selected.ok) return selected;
    const draft = draftText(c);
    if (draft.length > 60000) return {ok: false, error: 'The existing draft is too long for a Super Upload progress message.'};
    superUpload = {token: args.token, input: selected.input, documentID, phase: 'preparing',
      expectedDraft: null, expectedDraftKey: '', userIntent: false, intentAt: 0,
      baselineUserMessages: messageCounts().userMessages, baselineAssistantMessages: messageCounts().assistantMessages, baselineUserSignature: latestUserSignature(), baselineAssistantSignature: '',
      expectedFiles: [], attachmentBaseline: [], batchSerial: 0, appendedBatchSerial: null,
      appendedSuffix: '', appendedHref: '', appendedDocumentID: documentID, configuredOnce: false};
    return {...context(), ...messageCounts(), ok: true, accepted: selected.accepted, draft,
      languageSample: languageSample(), documentLanguage: String(document.documentElement?.lang || '').slice(0, 40),
      alertText: visibleAlertText()};
  }
  // NEW contract: called before native file handoff. It records the exact expected
  // basenames and the old attachment baseline; this is configuration, not success.
  function configureSuperUploadBatch(args) {
    if (!superUpload || superUpload.token !== args.token || superUpload.documentID !== documentID
        || !Array.isArray(args.expectedFiles) || args.expectedFiles.length > 100) return {ok: false, error: 'Invalid Super Upload batch configuration.'};
    const names = args.expectedFiles.map(basename).map(normalizedMessageText).filter(Boolean);
    if (names.length !== args.expectedFiles.length) return {ok: false, error: 'Expected file names must be non-empty basenames.'};
    // The first configuration belongs to the initial batch and must retain the
    // begin-time baseline, so a manual send before configuration is detected.
    // Later batches start after the prior batch's user message was observed.
    if (superUpload.configuredOnce) {
      const counts = messageCounts();
      superUpload.baselineUserMessages = counts.userMessages;
      superUpload.baselineAssistantMessages = counts.assistantMessages;
      superUpload.baselineUserSignature = latestUserSignature();
    }
    superUpload.configuredOnce = true;
    superUpload.expectedFiles = names; superUpload.boundFileNames = null;
    superUpload.phase = 'preparing';
    superUpload.batchSerial += 1; superUpload.appendedBatchSerial = null;
    superUpload.appendedSuffix = ''; superUpload.appendedHref = '';
    superUpload.userIntent = false; superUpload.intentAt = 0;
    superUpload.attachmentBaseline = composerAttachmentCards(composer()).map(card => card.name);
    return {ok: true, expectedFiles: names.slice(), attachmentBaseline: superUpload.attachmentBaseline.slice()};
  }
  // NEW contract: remove only uniquely matched failed cards using their own remove
  // control. Ambiguous or non-failed cards are never clicked.
  function removeFailedSuperUploadFiles(args) {
    if (!superUpload || superUpload.token !== args.token || !Array.isArray(args.names)) return {ok: false};
    const names = args.names.map(basename).map(normalizedMessageText).filter(Boolean);
    const cards = composerAttachmentCards(composer()).filter(failedCard);
    const targets = names.map(name => {
      const index = superUpload.expectedFiles.indexOf(name);
      const displayName = superUpload.boundFileNames?.[index] || name;
      const matches = cards.filter(card => card.name === displayName && cardRemoveControl(card));
      return matches.length === 1 ? matches[0] : null;
    });
    if (targets.some(target => !target)) return {ok: false, error: 'A failed file card could not be matched uniquely.'};
    targets.forEach(card => cardRemoveControl(card).click());
    superUpload.expectedFiles = superUpload.expectedFiles.filter(name => !names.includes(name));
    superUpload.boundFileNames = null;
    return {ok: true, expectedFiles: superUpload.expectedFiles.slice()};
  }
  function appendSuperUploadMessage(args) {
    const c = composer();
    if (!c || superUpload?.token !== args.token || superUpload.documentID !== documentID
        || typeof args.text !== 'string' || !args.text || args.text.length > 4000) {
      return {ok: false, error: 'The Super Upload progress message could not be prepared.'};
    }
    const automatic = args.automatic === true;
    const authorizeFirstSend = args.authorizeFirstSend === true;
    // A native Yes may authorise the first automatic send while preserving the
    // user's existing draft. Later automatic batches must still be append-only
    // and require an empty composer, so this exception is explicit and one-shot.
    if (authorizeFirstSend && (!automatic || superUpload.batchSerial !== 1)) {
      return {ok: false, error: 'The first-send authorisation is valid only for the initial automatic batch.'};
    }
    if (superUpload.phase !== 'preparing' || superUpload.appendedBatchSerial === superUpload.batchSerial) {
      return {ok: false, error: 'The Super Upload batch already has a prepared progress message.'};
    }
    // A trusted manual send can clear the composer before the native poller
    // reaches this call. Never append a stale first-batch note afterwards.
    if (messageCounts().userMessages > superUpload.baselineUserMessages
        || (superUpload.baselineUserSignature && latestUserSignature() !== superUpload.baselineUserSignature)
        || superUpload.userIntent) {
      return {ok: false, error: 'A message was already sent for this Super Upload batch. No progress message was appended.'};
    }
    const before = draftText(c);
    if (automatic && before.length && !authorizeFirstSend) return {ok: false, error: 'The message field changed while Super Upload was waiting. Nothing was overwritten or sent.'};
    const addition = `${before.length ? '\n\n' : ''}${args.text}`;
    if (before.length + addition.length > 65536) {
      return {ok: false, error: 'The existing instruction is too long to append a Super Upload progress message safely.'};
    }
    c.focus();
    if (!moveCaretToEnd(c)) return {ok: false, error: 'The end of the message field could not be selected safely.'};
    const inserted = document.execCommand('insertText', false, addition);
    const after = draftText(c);
    if (!inserted || after === before) return {ok: false, error: 'ChatGPT did not accept the Super Upload progress message.'};
    const counts = messageCounts();
    superUpload.phase = automatic ? 'ready-auto' : 'waiting-user';
    superUpload.expectedDraft = after; superUpload.expectedDraftKey = normalizedMessageText(after);
    superUpload.appendedSuffix = addition; superUpload.appendedDraft = after; superUpload.appendedPrefix = before; superUpload.appendedHref = href();
    superUpload.appendedDocumentID = documentID; superUpload.appendedBatchSerial = superUpload.batchSerial;
    superUpload.userIntent = false; superUpload.intentAt = 0;
    superUpload.baselineUserMessages = counts.userMessages;
    superUpload.baselineUserSignature = latestUserSignature();
    superUpload.baselineAssistantMessages = counts.assistantMessages;
    superUpload.baselineAssistantSignature = latestAssistantSignature();
    return {...context(), ...counts, ok: true, draft: after, alertText: visibleAlertText()};
  }
  function superUploadState(args) {
    const c = composer();
    if (!c || superUpload?.token !== args.token || superUpload.documentID !== documentID) {
      return {ok: false, error: 'The Super Upload session is no longer attached to this page.'};
    }
    const button = sendButton(c), uploading = uploadInProgress(c), counts = messageCounts();
    const busy = generationInProgress();
    const userMessageChanged = counts.userMessages > superUpload.baselineUserMessages
      || (!!latestUserSignature() && latestUserSignature() !== superUpload.baselineUserSignature);
    const submittedDraftMatches = userMessageChanged && lastUserMatchesExpected();
    const initialMessageAppeared = superUpload.phase === 'waiting-user'
      && (counts.userMessages > superUpload.baselineUserMessages
        || (superUpload.userIntent && submittedDraftMatches));
    if (initialMessageAppeared) superUpload.phase = 'initial-observed';
    const assistantSignature = latestAssistantSignature();
    const expectedFiles = superUpload.expectedFiles || [];
    const newCards = expectedNewCards();
    const boundNames = bindAttachmentNames(newCards, expectedFiles);
    if (boundNames !== null && !superUpload.userIntent && superUpload.phase !== 'auto-submitted') superUpload.boundFileNames = boundNames;
    const localCards = composerAttachmentCards(c);
    const failedByName = new Map();
    localCards.filter(failedCard).forEach(card => {
      const aliasIndex = superUpload.boundFileNames?.indexOf(card.name) ?? -1;
      const expectedName = aliasIndex >= 0 ? expectedFiles[aliasIndex] : expectedFiles.includes(card.name) ? card.name : null;
      if (!expectedName) return;
      const list = failedByName.get(expectedName) || []; list.push(card); failedByName.set(expectedName, list);
    });
    const failedFiles = Array.from(failedByName.entries()).filter(([, cards]) => cards.length === 1)
      .map(([name, cards]) => ({name, reason: String(cards[0].node.getAttribute?.('data-upload-error')
        || cards[0].node.querySelector?.('[role="alert"], [data-testid*="error"], [data-upload-error]')?.textContent || 'Upload failed').slice(0, 300)}));
    const attachmentError = Array.from(failedByName.values()).some(cards => cards.length > 1)
      ? 'An ambiguous attachment upload error requires manual review.' : '';
    const assistantResponseObserved = !!assistantSignature && assistantSignature !== superUpload.baselineAssistantSignature;
    const assistantTurn = assistantResponseObserved && Array.from(document.querySelectorAll('[data-message-author-role="assistant"]')).slice(-1)[0]?.closest?.('[data-testid^="conversation-turn-"], article');
    const latestUserTurn = Array.from(document.querySelectorAll('[data-message-author-role="user"]')).slice(-1)[0]?.closest?.('[data-testid^="conversation-turn-"], article');
    const followsSubmittedUser = submittedDraftMatches && !!latestUserTurn && !!assistantTurn
      && !!(latestUserTurn.compareDocumentPosition?.(assistantTurn) & 4);
    const submittedCards = latestUserTurn ? attachmentCards(latestUserTurn) : [];
    const submittedNames = superUpload.boundFileNames || expectedFiles;
    // Inactive/background WebKit can fade response controls to opacity:0. Keep
    // the strict new-assistant/new-user binding, but accept a settled non-empty
    // assistant turn when its action controls exist but are not visible.
    const responseActions = Array.from(assistantTurn?.querySelectorAll?.('[data-testid="copy-turn-action-button"], [data-testid*="turn-action"], button[aria-label*="Copy"]') || [])
      .filter(node => node.isConnected !== false);
    const responseTextPresent = normalizedMessageText(assistantTurn?.innerText || assistantTurn?.textContent || '').length > 0;
    const responseCompletionEvidence = responseActions.some(visible)
      || (responseActions.length > 0 && responseTextPresent && idleResponseControl(c));
    const assistantResponseComplete = assistantResponseObserved && followsSubmittedUser && !busy && !!assistantTurn
      && responseCompletionEvidence;
    return {...context(), ...counts, ok: true, phase: superUpload.phase,
      draft: draftText(c), draftMatchesExpected: draftMatchesExpected(c),
      lastUserMatchesExpected: submittedDraftMatches,
      expectedDraft: superUpload.expectedDraft,
      expectedFiles: expectedFiles.slice(),
      attachmentCount: newCards.length,
      attachmentsReady: !uploading && !failedByName.size && boundNames !== null,
      failedFiles, attachmentError,
      assistantResponseObserved, assistantResponseComplete, assistantSignature,
      submittedAttachmentsMatch: !!latestUserTurn && submittedDraftMatches && superUpload.boundFileNames !== null && cardsMatchNames(submittedCards, submittedNames),
      submittedAttachmentCount: submittedCards.length,
      unconfirmedFiles: submittedNames.filter(name => !submittedCards.some(card => card.name === name)),
      userIntent: superUpload.userIntent, intentAt: superUpload.intentAt, uploading,
      busy, idleResponseControl: !busy && idleResponseControl(c),
      sendReady: !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true' && !uploading && !busy,
      alertText: visibleAlertText()};
  }
  function submitSuperUpload(args) {
    const c = composer();
    if (!c || superUpload?.token !== args.token || superUpload.documentID !== documentID
        || superUpload.phase !== 'ready-auto' || typeof args.expectedDraft !== 'string'
        || normalizedMessageText(draftText(c)) !== normalizedMessageText(args.expectedDraft)) {
      return {ok: false, error: 'The automatic Super Upload message changed and was not sent.'};
    }
    const button = sendButton(c);
    if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true' || uploadInProgress(c)
        || generationInProgress()) {
      return {ok: false, error: 'ChatGPT is not ready to send the next Super Upload batch.'};
    }
    const counts = messageCounts();
    superUpload.phase = 'auto-submitted';
    button.click();
    return {...context(), ...counts, ok: true, requested: true, alertText: visibleAlertText()};
  }
  function endSuperUpload(args) {
    if (!superUpload || superUpload.token !== args.token) return {ok: false};
    removePreparedSuffix(superUpload);
    superUpload = null; return {ok: true};
  }
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
    if (event.isTrusted && ['waiting-user', 'preparing'].includes(superUpload?.phase)) {
      const c = composer(), button = sendButton(c);
      if (button && (event.target === button || button.contains?.(event.target))) {
        superUpload.userIntent = true; superUpload.intentAt = Date.now();
        superUpload.expectedDraft = draftText(c); superUpload.expectedDraftKey = normalizedMessageText(superUpload.expectedDraft);
      }
    }
    // Conservative session-memory clearing on explicit account/workspace UI interaction.
    // This is NOT a reliable account identifier, so there is no automatic draft reinsertion.
    if (event.isTrusted && event.target?.closest?.('[data-testid="profile-button"], [data-testid="accounts-profile-button"], [data-testid="workspace-switcher"], a[href*="/auth/logout"]')) {
      cancelFiles(); removePreparedSuffix(superUpload); superUpload = null; post({kind: 'privacyBoundary'});
    }
  }
  function onKeyDown(event) {
    if (!event.isTrusted || !['waiting-user', 'preparing'].includes(superUpload?.phase) || event.isComposing
        || event.key !== 'Enter' || event.shiftKey || event.altKey || event.ctrlKey || event.metaKey) return;
    const c = composer();
    if (c && (event.target === c || c.contains(event.target))) {
      superUpload.userIntent = true; superUpload.intentAt = Date.now();
      if (normalizedMessageText(draftText(c))) {
        superUpload.expectedDraft = draftText(c); superUpload.expectedDraftKey = normalizedMessageText(superUpload.expectedDraft);
      }
    }
  }
  function onSubmit(event) {
    const c = composer();
    if (event.isTrusted && ['waiting-user', 'preparing'].includes(superUpload?.phase) && c?.closest('form') === event.target) {
      superUpload.userIntent = true; superUpload.intentAt = Date.now();
      if (normalizedMessageText(draftText(c))) {
        superUpload.expectedDraft = draftText(c); superUpload.expectedDraftKey = normalizedMessageText(superUpload.expectedDraft);
      }
    }
  }
  function teardown() {
    disposed = true; clearTimeout(draftTimer); cancelFiles(); removePreparedSuffix(superUpload); superUpload = null;
    document.removeEventListener('input', onInput, true);
    document.removeEventListener('click', onClick, true);
    document.removeEventListener('copy', onCopy, true);
    document.removeEventListener('keydown', onKeyDown, true);
    document.removeEventListener('submit', onSubmit, true);
    document.getElementById('chatdesk-reading-style')?.remove();
    delete globalThis.ChatDeskAdapter;
    return {ok: true};
  }
  document.addEventListener('input', onInput, true);
  document.addEventListener('click', onClick, true);
  document.addEventListener('copy', onCopy, true);
  document.addEventListener('keydown', onKeyDown, true);
  document.addEventListener('submit', onSubmit, true);
  globalThis.ChatDeskAdapter = Object.freeze({context, prepareFiles, triggerFiles, validateFiles,
    cancelFiles, beginSuperUpload, configureSuperUploadBatch, removeFailedSuperUploadFiles,
    appendSuperUploadMessage, superUploadState, submitSuperUpload,
    endSuperUpload, getDraft, insertText, selectedText, applyReading, teardown});
})();
