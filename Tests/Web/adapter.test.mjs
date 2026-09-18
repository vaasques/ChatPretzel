import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const source=fs.readFileSync(new URL('../../Sources/ChatDeskMac/Resources/Adapter.js',import.meta.url),'utf8');
function environment({host='chatgpt.com',inputs=[{}],focused=true,selectionText='',draft='keep',
                      documentLanguage='en',autoReply=true,attachments=[],observedFileMarkup=false,
                      idleVoice=false}={}) {
  const listeners=new Map(),calls=[],userMessages=[],assistantMessages=[],copyActions=[],alerts=[],conversationTurns=[];
  const copiedTypes=new Map(),ranges=[];
  let uploading=false,busy=false,submitted=0,form,turnSerial=0;
  const orderedTurn=properties=>({isConnected:true,...properties,
    getAttribute(name){return name==='data-testid'?this.testid:null},
    closest(selector){return selector.includes('conversation-turn-')||selector==='article'?this:null},
    compareDocumentPosition(other){return this===other?0:(this.order<other.order?4:2)},
    order:turnSerial++,testid:`conversation-turn-${turnSerial}`});
  const attachmentNodes=attachments.map(({name,status='',hidden=false}={})=>{
    const removeLabel=observedFileMarkup ? `Ta bort fil 1: ${name}` : 'Remove file';
    const fileButton=observedFileMarkup
      ? {hidden:false,isConnected:true,innerText:name,getAttribute(key){return key==='aria-label'?name:null},click(){this.clicked=true}}
      : null;
    const remove={hidden:false,isConnected:true,getAttribute(key){return key==='aria-label'?removeLabel:null},click(){this.removed=true}};
    const card={hidden,isConnected:true,role:observedFileMarkup?'group':undefined,innerText:observedFileMarkup?`${name}\nFil`:name,
      getAttribute(key){
        if (observedFileMarkup) return key==='role'?'group':key==='aria-label'?name:key==='data-upload-status'?status:null;
        return key==='data-file-name'?name:key==='data-upload-status'?status:null;
      },
      hasAttribute(key){return observedFileMarkup && key==='aria-label'},
      matches(selector){return observedFileMarkup && selector.includes('[role="group"]')},
      querySelectorAll(selector){
        if (selector.includes('button') || selector.includes('[role="button"]')) return observedFileMarkup?[fileButton,remove]:[remove];
        return [];
      },closest(){return null}};
    if (observedFileMarkup) { fileButton.parentElement=card; remove.parentElement=card; }
    return card;
  });
  const selection={get rangeCount(){return ranges.length},getRangeAt(index){return ranges[index]},
    removeAllRanges(){ranges.length=0},addRange(range){ranges.push(range)},
    toString(){return ranges.length?String(ranges[0].text||''):selectionText}};
  const location={protocol:'https:',hostname:host,href:`https://${host}/c/one`,pathname:'/c/one',search:''};
  const fileInputs=inputs.map(properties=>({disabled:false,multiple:true,isConnected:true,accept:'',dataset:{},
    getAttribute(name){return this[name]??null},
    closest(selector){if(selector==='input[type="file"]')return this;if(selector==='form')return form;return null},
    click(){calls.push('click');listeners.get('click')?.({target:this,isTrusted:false});},...properties}));
  let document;
  const composer={tagName:'TEXTAREA',value:draft,isConnected:true,
    setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end},
    contains(e){return e===this},
    closest(selector){return selector==='form'?form:null},focus(){document.activeElement=this}};
  function submitCurrent(trusted=false){
    listeners.get('submit')?.({isTrusted:trusted,target:form});
    userMessages.push({innerText:composer.value});composer.value='';submitted++;
    if(autoReply)assistantMessages.push({innerText:'Fixture reply'});
  }
  const sendButton={isConnected:true,disabled:false,dataset:{testid:'send-button'},ariaDisabled:null,
    getAttribute(name){return name==='aria-disabled'?this.ariaDisabled:null},
    contains(target){return target===this},
    click(){calls.push('send');listeners.get('click')?.({target:this,isTrusted:false});submitCurrent(false)}};
  const idleVoiceButton={isConnected:true,hidden:false,getClientRects(){return [{}]},
    getAttribute(name){return name==='aria-label'?'Voice mode':null}};
  const uploadMarker={isConnected:true};
  const stopButton={isConnected:true};
  form={
    matches(selector){return uploading&&selector.includes('[data-state="uploading"]')},
    querySelector(selector){
      if(selector==='button[data-testid="send-button"]')return sendButton;
      if(idleVoice && (selector.includes('voice-mode-button') || selector.includes('chatdesk-idle-control'))) return idleVoiceButton;
      if(uploading&&selector.includes('upload'))return uploadMarker;
      return null;
    },
    querySelectorAll(selector){
      if(selector==='input[type="file"]')return fileInputs;
      if(!observedFileMarkup && (selector.includes('attachment') || selector.includes('data-file-name') || selector.includes('data-filename')))return attachmentNodes;
      if(observedFileMarkup && selector.includes('[role="group"][aria-label]'))return attachmentNodes;
      if(observedFileMarkup && (selector.includes('button[aria-label]') || selector.includes('[role="button"][aria-label]')))
        return attachmentNodes.flatMap(card=>card.querySelectorAll('button[aria-label]'));
      if(selector.includes('stop-button'))return busy?[stopButton]:[];
      if(selector==='button[type="submit"]')return [sendButton];
      return [];
    }
  };
  attachmentNodes.forEach(card=>{card.parentElement=form;});
  document={activeElement:focused?composer:{},documentElement:{lang:documentLanguage},head:{append(){}},
    querySelector(selector){
      if(selector.includes('#prompt-textarea'))return composer;
      if(selector==='[data-testid="stop-button"]')return busy?stopButton:null;
      if(uploading&&(selector.includes('progressbar')||selector.includes('upload')))return uploadMarker;
      return null;
    },
    querySelectorAll(selector){
      if(selector==='input[type="file"]')return fileInputs;
      if(selector==='[data-message-author-role="user"]')return userMessages;
      if(selector==='[data-message-author-role="assistant"]')return assistantMessages;
      if(selector==='[data-testid="copy-turn-action-button"]')return copyActions;
      if(selector==='[data-testid^="conversation-turn-"]')return conversationTurns;
      if(selector==='[role="alert"]')return alerts;
      if(selector.includes('stop-button'))return busy?[stopButton]:[];
      if(!observedFileMarkup && (selector.includes('attachment') || selector.includes('data-file-name') || selector.includes('data-filename')))return attachmentNodes;
      if(observedFileMarkup && selector.includes('[role="group"][aria-label]'))return attachmentNodes;
      if(observedFileMarkup && (selector.includes('button[aria-label]') || selector.includes('[role="button"][aria-label]')))
        return attachmentNodes.flatMap(card=>card.querySelectorAll('button[aria-label]'));
      return [];
    },addEventListener(type,f){listeners.set(type,f)},removeEventListener(type){listeners.delete(type)},
    getElementById(){return null},createElement(){return {id:'',textContent:'',remove(){}}},
    createRange(){return {text:'',selectNodeContents(node){this.text=node.innerText},cloneRange(){return {...this}}}},
    execCommand(command,_,text){
      if(command==='insertText'){composer.value+=text;return true}
      if(command==='copy'){
        let prevented=false;
        listeners.get('copy')?.({isTrusted:true,clipboardData:{clearData(){copiedTypes.clear()},setData(type,value){copiedTypes.set(type,value)}},
          preventDefault(){prevented=true},stopImmediatePropagation(){}});
        return prevented;
      }
      return false;
    }};
  const messages=[];
  const context={document,location,URLSearchParams,Date,Math,crypto:{randomUUID:()=> 'doc-1'},
    setTimeout,clearTimeout,console,getSelection:()=>selection,
    webkit:{messageHandlers:{chatdesk:{postMessage:value=>messages.push(value)}}}};
  vm.runInNewContext(source,context);
  return {adapter:context.ChatDeskAdapter,location,inputs:fileInputs,composer,document,listeners,calls,messages,copiedTypes,
    sendButton,userMessages,assistantMessages,alerts,attachmentNodes,get submitted(){return submitted},
    setUploading(value){uploading=value},setBusy(value){busy=value},
    seedAssistantRole(text='Previous answer') {
      const turn=orderedTurn({innerText:text,textContent:text,querySelector(){return null},querySelectorAll(){return []}});
      const message={innerText:text,textContent:text,closest(){return turn}};
      turn.querySelector=selector=>selector==='[data-message-author-role="assistant"]'?message:null;
      conversationTurns.push(turn);assistantMessages.push(message);return turn;
    },
    seedCopyBackedAnswer(text='Previous copy-backed answer') {
      const turn=orderedTurn({innerText:text,textContent:text,querySelector(){return null},querySelectorAll(){return []}});
      const action={isConnected:true,closest(){return turn}};
      conversationTurns.push(turn);copyActions.push(action);return turn;
    },
    seedUserTurn(text='First batch',{roleNode=true}={}) {
      const turn=orderedTurn({innerText:text,textContent:text,querySelector(){return null},querySelectorAll(selector){
        if(selector.includes('attachment')||selector.includes('data-file-name')||selector.includes('data-filename'))return attachmentNodes;
        return [];
      }});
      const message={innerText:text,textContent:text,closest(){return turn}};
      if(roleNode){userMessages.push(message);turn.querySelector=selector=>selector==='[data-message-author-role="user"]'?message:null;}
      conversationTurns.push(turn);return turn;
    },
    setReplyState({actions='visible',text='Completed reply',roleNode=true,userRoleNode=true}={}) {
      const actionNodes=actions==='none'?[]:[{isConnected:true,hidden:actions==='hidden',getClientRects(){return actions==='hidden'?[]:[{}]},getAttribute(){return null}}];
      const userTurn=orderedTurn({innerText:'First batch',textContent:'First batch',
        querySelector(){return null},querySelectorAll(selector){
          if(selector.includes('attachment')||selector.includes('data-file-name')||selector.includes('data-filename'))return attachmentNodes;
          return [];
        }});
      const userMessage={innerText:'First batch',textContent:'First batch',closest(){return userTurn}};
      if(userRoleNode){userMessages.push(userMessage);userTurn.querySelector=selector=>selector==='[data-message-author-role="user"]'?userMessage:null;}
      const assistantTurn=orderedTurn({innerText:text,textContent:text,
        querySelector(){return null},querySelectorAll(){return actionNodes}});
      const assistantMessage={innerText:text,textContent:text,closest(){return assistantTurn}};
      if(roleNode){assistantMessages.push(assistantMessage);assistantTurn.querySelector=selector=>selector==='[data-message-author-role="assistant"]'?assistantMessage:null;}
      for(const action of actionNodes)action.closest=()=>assistantTurn;
      if(!roleNode)copyActions.push(...(actionNodes.length?actionNodes:[{isConnected:true,closest(){return assistantTurn}}]));
      conversationTurns.push(userTurn,assistantTurn);
    },
    trustedEnter(){listeners.get('keydown')?.({isTrusted:true,isComposing:false,key:'Enter',shiftKey:false,
      altKey:false,ctrlKey:false,metaKey:false,target:composer});submitCurrent(true)}};
}
const files=[{extension:'pdf',mime:'application/pdf'},{extension:'png',mime:'image/png'}];
test('Does not install on an untrusted host',()=>assert.equal(environment({host:'evil.test'}).adapter,undefined));
test('Preserves ordinary composer text',()=>{const e=environment();assert.equal(e.adapter.getDraft().text,'keep');});
test('One eligible input prepares entire mixed batch without clicking',()=>{const e=environment();assert.equal(e.adapter.prepareFiles({token:'op',files,requireFocus:true}).ok,true);assert.equal(e.calls.length,0);});
test('Requires focused composer for paste',()=>{const e=environment({focused:false});assert.equal(e.adapter.prepareFiles({token:'op',files,requireFocus:true}).ok,false);});
test('Rejects single-file controls for a batch',()=>{const e=environment({inputs:[{multiple:false}]});assert.equal(e.adapter.prepareFiles({token:'op',files}).ok,false);});
test('Honors the real accept restriction',()=>{const e=environment({inputs:[{accept:'image/*'}]});assert.equal(e.adapter.prepareFiles({token:'op',files}).ok,false);});
test('Selects the only input accepting all types',()=>{const e=environment({inputs:[{accept:'image/*'},{}]});assert.equal(e.adapter.prepareFiles({token:'op',files}).ok,true);});
test('Refuses ambiguous inputs',()=>{const e=environment({inputs:[{},{}]});assert.equal(e.adapter.prepareFiles({token:'op',files}).ok,false);});
test('Does not mutate accept or multiple',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});e.adapter.triggerFiles({token:'op'});assert.equal(e.inputs[0].accept,'');assert.equal(e.inputs[0].multiple,true);assert.equal(e.calls.length,1);});
test('Validation requires the selected input to have been triggered',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});assert.equal(e.adapter.validateFiles({token:'op'}).ok,false);e.adapter.triggerFiles({token:'op'});assert.equal(e.adapter.validateFiles({token:'op'}).ok,true);});
test('Wrong token cannot trigger picker',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});assert.equal(e.adapter.triggerFiles({token:'wrong'}).ok,false);assert.equal(e.calls.length,0);});
test('Changing route cancels before file delivery',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});e.location.href='https://chatgpt.com/c/two';assert.equal(e.adapter.triggerFiles({token:'op'}).ok,false);});
test('Disconnected input cannot trigger',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});e.inputs[0].isConnected=false;assert.equal(e.adapter.triggerFiles({token:'op'}).ok,false);});
test('Manual cancellation invalidates validation',()=>{const e=environment();e.adapter.prepareFiles({token:'op',files});e.adapter.triggerFiles({token:'op'});e.adapter.cancelFiles();assert.equal(e.adapter.validateFiles({token:'op'}).ok,false);});
test('Draft restore cannot overwrite nonempty editor',()=>{const e=environment();assert.equal(e.adapter.insertText({text:'old',onlyIfEmpty:true}).ok,false);assert.equal(e.composer.value,'keep');});
test('Prompt insertion does not submit anything',()=>{const e=environment();assert.equal(e.adapter.insertText({text:' new'}).ok,true);assert.equal(e.composer.value,'keep new');assert.equal(e.calls.length,0);});
test('Selected text is returned without HTML formatting',()=>{const e=environment({selectionText:'Dark HTML becomes plain text'});const result=e.adapter.selectedText();assert.equal(result.ok,true);assert.equal(result.text,'Dark HTML becomes plain text');});
test('Empty selection is not written to the clipboard',()=>{const result=environment().adapter.selectedText();assert.equal(result.ok,false);assert.equal(result.text,undefined);});
test('Trusted copy exposes only plain text for Outlook',()=>{
  const e=environment({selectionText:'Readable text'}),written=new Map();
  let prevented=false,stopped=false,cleared=false;
  e.listeners.get('copy')({isTrusted:true,clipboardData:{clearData(){cleared=true;written.clear()},setData(type,value){written.set(type,value)}},
    preventDefault(){prevented=true},stopImmediatePropagation(){stopped=true}});
  assert.equal(prevented,true);assert.equal(stopped,true);assert.equal(cleared,true);
  assert.equal(written.get('text/plain'),'Readable text');assert.equal(written.has('text/html'),false);
});
test('Synthetic copy cannot write clipboard data',()=>{
  const e=environment({selectionText:'private'});let writes=0;
  e.listeners.get('copy')({isTrusted:false,clipboardData:{clearData(){writes++},setData(){writes++}},preventDefault(){writes++},stopImmediatePropagation(){writes++}});
  assert.equal(writes,0);
});
test('ChatGPT copy button writes the message as plain text',()=>{
  const e=environment(),message={innerText:'Answer without dark HTML'};
  const turn={querySelector:selector=>selector==='[data-message-author-role]'?message:null};
  const button={closest:selector=>selector==='[data-testid^="conversation-turn-"], article'?turn:null};
  const target={closest:selector=>selector==='[data-testid="copy-turn-action-button"]'?button:null};
  let prevented=false,stopped=false;
  e.listeners.get('click')({isTrusted:true,target,preventDefault(){prevented=true},stopImmediatePropagation(){stopped=true}});
  assert.equal(prevented,true);assert.equal(stopped,true);
  assert.equal(e.copiedTypes.get('text/plain'),'Answer without dark HTML');
  assert.equal(e.copiedTypes.has('text/html'),false);
});
test('Temporary chat query is recognized',()=>{const e=environment();e.location.search='?temporary-chat=true';assert.equal(e.adapter.getDraft().temporary,true);});
test('Teardown removes listeners',()=>{const e=environment();e.adapter.teardown();assert.equal(e.listeners.size,0);});

test('Oversized draft is rejected without silent truncation',()=>{const e=environment();e.composer.value='x'.repeat(65537);const result=e.adapter.getDraft();assert.equal(result.ok,false);assert.equal(result.text,undefined);assert.equal(e.composer.value.length,65537);});

test('Super Upload chooses the control accepting the most files and returns a type mask',()=>{
  const e=environment({inputs:[{accept:'image/*'},{accept:'application/pdf'}]});
  const result=e.adapter.beginSuperUpload({token:'super',requireFocus:true,types:[
    {extension:'png',mime:'image/png',count:2},{extension:'pdf',mime:'application/pdf',count:10}]});
  assert.equal(result.ok,true);assert.deepEqual(Array.from(result.accepted),[false,true]);
});
test('Super Upload identifies when every supplied type is unsupported',()=>{
  const e=environment({inputs:[{accept:'image/*'}]});
  const result=e.adapter.beginSuperUpload({token:'super',types:[{extension:'pdf',mime:'application/pdf',count:25}]});
  assert.equal(result.ok,false);assert.equal(result.unsupportedAll,true);
});
test('Super Upload preserves the existing instruction above its first progress message',()=>{
  const e=environment({draft:'Analyse these files'});
  assert.equal(e.adapter.beginSuperUpload({token:'super',types:files}).ok,true);
  const result=e.adapter.appendSuperUploadMessage({token:'super',text:'Files 1–10 of 25.',automatic:false});
  assert.equal(result.ok,true);assert.equal(e.composer.value,'Analyse these files\n\nFiles 1–10 of 25.');
});
test('A wrong Super Upload token cannot append or submit',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  assert.equal(e.adapter.appendSuperUploadMessage({token:'wrong',text:'No',automatic:false}).ok,false);
  assert.equal(e.adapter.submitSuperUpload({token:'wrong',expectedDraft:'keep'}).ok,false);
  assert.equal(e.submitted,0);
});
test('A manually sent first batch blocks a stale progress append while preparing',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.userMessages.push({innerText:'First batch sent by user'});
  const result=e.adapter.appendSuperUploadMessage({token:'super',text:'Batch 1 of 148',automatic:false});
  assert.equal(result.ok,false); assert.equal(e.composer.value,'');
});
test('Only the exact app-added suffix is removed on end, preserving user edits',()=>{
  const e=environment({draft:'User instruction'}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'Batch 1 of 148',automatic:false});
  e.composer.value='Edited instruction\n\nBatch 1 of 148';
  assert.equal(e.adapter.endSuperUpload({token:'super'}).ok,true);
  assert.equal(e.composer.value,'Edited instruction');
});
test('Ending after a route change does not clear a new-chat draft',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'Batch 1 of 148',automatic:false});
  e.location.href='https://chatgpt.com/c/new';
  e.composer.value='New chat draft';
  assert.equal(e.adapter.endSuperUpload({token:'super'}).ok,true);
  assert.equal(e.composer.value,'New chat draft');
});
test('A configured batch accepts at most one progress append',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  assert.equal(e.adapter.appendSuperUploadMessage({token:'super',text:'Batch 1',automatic:false}).ok,true);
  assert.equal(e.adapter.appendSuperUploadMessage({token:'super',text:'Batch 1 again',automatic:false}).ok,false);
});
test('The first Super Upload batch cannot be sent programmatically',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  const prepared=e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  assert.equal(e.adapter.submitSuperUpload({token:'super',expectedDraft:prepared.draft}).ok,false);
  assert.equal(e.submitted,0);
});
test('One trusted Enter marks the initial Super Upload send intent',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.listeners.get('keydown')({isTrusted:true,isComposing:false,key:'Enter',shiftKey:false,
    altKey:false,ctrlKey:false,metaKey:false,target:e.composer});
  assert.equal(e.adapter.superUploadState({token:'super'}).userIntent,true);
});
test('Trusted first intent captures an edited draft exactly',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.composer.value='First batch edited by user';
  e.listeners.get('keydown')({isTrusted:true,isComposing:false,key:'Enter',shiftKey:false,
    altKey:false,ctrlKey:false,metaKey:false,target:e.composer});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.expectedDraft,'First batch edited by user');
  assert.equal(state.draftMatchesExpected,true);
});
test('Super Upload tolerates harmless WebKit whitespace normalization',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch\nPlease wait.',automatic:false});
  e.composer.value=' First\u00a0batch\r\nPlease   wait.\n';
  assert.equal(e.adapter.superUploadState({token:'super'}).draftMatchesExpected,true);
});
test('Super Upload can corroborate a submitted first message after the composer clears',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.composer.value='';
  let state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.userIntent,false);assert.equal(state.userMessages,0);
  assert.equal(state.draftMatchesExpected,false);
  e.userMessages.push({innerText:'First batch'});
  state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.userMessages,1);assert.equal(state.lastUserMatchesExpected,true);
});
test('Super Upload confirms a collapsed first message from its full DOM text',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  const expected='Files 1–10 of 1481 are attached. 1471 more files will follow.';
  e.adapter.appendSuperUploadMessage({token:'super',text:expected,automatic:false});
  // Current ChatGPT can render a long user message as a visible excerpt plus a
  // localized “Visa mer” control while retaining the complete content in DOM.
  e.userMessages.push({innerText:'Files 1–10 of 1481 are attached. Visa mer',textContent:expected});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.lastUserMatchesExpected,true);
  assert.equal(state.submittedAttachmentsMatch,true);
});
test('Super Upload survives virtualized message counts that stay constant',()=>{
  const e=environment({draft:'',autoReply:false});
  e.userMessages.push({innerText:'Older user turn'});
  e.assistantMessages.push({innerText:'Older assistant turn'});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.listeners.get('keydown')({isTrusted:true,isComposing:false,key:'Enter',shiftKey:false,
    altKey:false,ctrlKey:false,metaKey:false,target:e.composer});
  e.composer.value='';
  e.userMessages[0]={innerText:'First batch'};
  let state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.userMessages,1);
  assert.equal(state.userIntent,true);
  assert.equal(state.lastUserMatchesExpected,true);
  assert.equal(state.assistantResponseObserved,false);
  e.assistantMessages[0]={innerText:'New completed assistant response'};
  state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantMessages,1);
  assert.equal(state.assistantResponseObserved,true);
});
test('Completed background response accepts hidden actions with an idle control',()=>{
  const e=environment({draft:'',idleVoice:true});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'hidden'});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,true);assert.equal(state.assistantResponseComplete,true);
});
test('Completed response without action controls accepts the explicit idle composer state',()=>{
  const e=environment({draft:'',idleVoice:true});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none'});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,true);assert.equal(state.assistantResponseComplete,true);
  assert.equal(state.assistantResponseActionCount,0);assert.equal(state.responseCompletionEvidence,true);
});
test('Copy-action fallback can bind a completed response without an assistant role node',()=>{
  const e=environment({draft:'',idleVoice:true});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none',roleNode:false});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,true);assert.equal(state.assistantResponseComplete,true);
  assert.equal(state.assistantTurnFound,true);
});
test('A newer copy-backed answer wins over an older retained assistant role node',()=>{
  const e=environment({draft:'',idleVoice:true});e.seedAssistantRole('Previous answer');
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none',roleNode:false});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,true);assert.equal(state.assistantTurnFound,true);
  assert.equal(state.assistantResponseComplete,true);
});
test('A newer assistant role node wins over an older retained copy action',()=>{
  const e=environment({draft:'',idleVoice:true});e.seedCopyBackedAnswer();
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none',roleNode:true});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,true);assert.equal(state.assistantResponseComplete,true);
});
test('An old copy-backed answer cannot confirm a new batch without a fresh answer',()=>{
  const e=environment({draft:'',idleVoice:true});e.seedCopyBackedAnswer();
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none',roleNode:false,text:''});
  // Remove the synthetic fresh fallback action and its empty turn. Only the
  // answer that existed at beginSuperUpload remains as assistant evidence.
  e.document.querySelectorAll('[data-testid="copy-turn-action-button"]').splice?.(1);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.assistantResponseObserved,false);assert.equal(state.assistantResponseComplete,false);
});
test('A role-less sent user turn is bound by exact text and exact attachments',()=>{
  const e=environment({draft:'',idleVoice:true,attachments:[]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  const card={hidden:false,isConnected:true,innerText:'a.pdf',
    getAttribute(name){return name==='data-file-name'?'a.pdf':null},hasAttribute(){return false},matches(){return false},
    querySelectorAll(){return []},closest(){return null}};
  e.attachmentNodes.push(card);
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,true);
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'none',userRoleNode:false});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.lastUserTextMatchesExpected,true);assert.equal(state.userMessageChanged,true);
  assert.equal(state.submittedUserTurnFound,true);assert.equal(state.submittedAttachmentsMatch,true);
  assert.equal(state.followsSubmittedUser,true);assert.equal(state.assistantResponseComplete,true);
});
test('An explicitly assistant-attributed turn cannot impersonate the submitted user batch',()=>{
  const e=environment({draft:'',attachments:[{name:'a.pdf'}]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  const assistantTurn=e.seedAssistantRole('First batch');
  assistantTurn.querySelectorAll=selector=>(selector.includes('attachment')||selector.includes('data-file-name')||selector.includes('data-filename'))?e.attachmentNodes:[];
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.lastUserTextMatchesExpected,false);assert.equal(state.lastUserMatchesExpected,false);
  assert.equal(state.submittedAttachmentsMatch,false);
});
test('A later different user message cannot make an older matching batch look fresh',()=>{
  const e=environment({draft:'',attachments:[{name:'a.pdf'}]});
  e.seedUserTurn('First batch');
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.seedUserTurn('A different message');
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.lastUserTextMatchesExpected,true);assert.equal(state.userMessageChanged,false);
  assert.equal(state.lastUserMatchesExpected,false);assert.equal(state.submittedAttachmentsMatch,false);
});
test('Hidden response actions without an idle control are not completion evidence',()=>{
  const e=environment({draft:'',idleVoice:false});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'hidden'});
  assert.equal(e.adapter.superUploadState({token:'super'}).assistantResponseComplete,false);
});
test('A busy response is never complete even with hidden actions and idle control',()=>{
  const e=environment({draft:'',idleVoice:true});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[]});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.setReplyState({actions:'hidden'});e.setBusy(true);
  assert.equal(e.adapter.superUploadState({token:'super'}).assistantResponseComplete,false);
});
test('An automatic Super Upload batch refuses to overwrite a nonempty composer',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  assert.equal(e.adapter.appendSuperUploadMessage({token:'super',text:'Next batch',automatic:true}).ok,false);
  assert.equal(e.composer.value,'keep');
});
test('Authorised automatic first batch preserves an existing draft',()=>{
  const e=environment({draft:'Analyse these files'});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  const prepared=e.adapter.appendSuperUploadMessage({token:'super',text:'Files 1–10 of 25.',automatic:true,authorizeFirstSend:true});
  assert.equal(prepared.ok,true);
  assert.equal(prepared.draft,'Analyse these files\n\nFiles 1–10 of 25.');
  assert.equal(e.adapter.submitSuperUpload({token:'super',expectedDraft:prepared.draft}).ok,true);
});
test('First-send authorisation cannot be reused for a later automatic batch',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf']});
  const first=e.adapter.appendSuperUploadMessage({token:'super',text:'First',automatic:true,authorizeFirstSend:true});
  assert.equal(first.ok,true);e.adapter.submitSuperUpload({token:'super',expectedDraft:first.draft});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['b.pdf']});
  e.composer.value='User changed this draft';
  assert.equal(e.adapter.appendSuperUploadMessage({token:'super',text:'Second',automatic:true,authorizeFirstSend:true}).ok,false);
  assert.equal(e.composer.value,'User changed this draft');
});
test('An automatic Super Upload batch sends only its exact prepared message',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  const prepared=e.adapter.appendSuperUploadMessage({token:'super',text:'Files 11–20 of 25.',automatic:true});
  const result=e.adapter.submitSuperUpload({token:'super',expectedDraft:prepared.draft});
  assert.equal(result.ok,true);assert.equal(e.submitted,1);assert.equal(e.userMessages[0].innerText,'Files 11–20 of 25.');
});
test('Editing an automatic Super Upload message prevents sending',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  const prepared=e.adapter.appendSuperUploadMessage({token:'super',text:'Next batch',automatic:true});
  e.composer.value+=' changed';
  assert.equal(e.adapter.submitSuperUpload({token:'super',expectedDraft:prepared.draft}).ok,false);
  assert.equal(e.submitted,0);
});
test('Super Upload reports upload progress and disables send readiness',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'Next batch',automatic:true});
  e.setUploading(true);const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.uploading,true);assert.equal(state.sendReady,false);
});
test('The generation stop control is treated as busy and prevents automatic send',()=>{
  const e=environment({draft:''});e.adapter.beginSuperUpload({token:'super',types:files});
  const prepared=e.adapter.appendSuperUploadMessage({token:'super',text:'Next batch',automatic:true});
  e.setBusy(true);const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.busy,true);assert.equal(state.idleResponseControl,false);assert.equal(state.sendReady,false);
  assert.equal(e.adapter.submitSuperUpload({token:'super',expectedDraft:prepared.draft}).ok,false);
  assert.equal(e.submitted,0);
});
test('An overlong first instruction is not changed by Super Upload',()=>{
  const original='x'.repeat(65530),e=environment({draft:original});
  assert.equal(e.adapter.beginSuperUpload({token:'super',types:files}).ok,false);
  assert.equal(e.composer.value,original);
});
test('Ending Super Upload invalidates its token',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  assert.equal(e.adapter.endSuperUpload({token:'super'}).ok,true);
  assert.equal(e.adapter.superUploadState({token:'super'}).ok,false);
});
test('Batch configuration captures exact basenames and attachment baseline',()=>{
  const e=environment({attachments:[{name:'old.pdf'}]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  const result=e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['/tmp/Äldre.pdf','new.png']});
  assert.equal(result.ok,true); assert.deepEqual(result.expectedFiles,['Äldre.pdf','new.png']);
  assert.deepEqual(Array.from(result.attachmentBaseline),['old.pdf']);
});
test('Attachment readiness requires every visible expected card and no upload marker',()=>{
  const e=environment({draft:'',attachments:[]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['a.pdf','b.png']});
  e.attachmentNodes.push(...environment({attachments:[{name:'a.pdf'},{name:'b.png'}]}).attachmentNodes);
  const ready=e.adapter.superUploadState({token:'super'}); assert.equal(ready.attachmentsReady,true);
  e.setUploading(true); assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,false);
});
test('Observed ChatGPT composer card uses accessible filename evidence without data attributes',()=>{
  const name='report.pdf',e=environment({draft:'',attachments:[],observedFileMarkup:true});
  const card=environment({attachments:[{name:'report(1).pdf'}],observedFileMarkup:true}).attachmentNodes[0];
  assert.equal(card.getAttribute('data-testid'),null);
  assert.equal(card.getAttribute('title'),null);
  assert.equal(card.getAttribute('aria-label'),'report(1).pdf');
  assert.equal(card.innerText,'report(1).pdf\nFil');
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});
  e.attachmentNodes.push(card);
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,true);
});
test('Observed localized remove control is matched by its exact aria-label',()=>{
  const name='meeting_audit(1).md',e=environment({draft:'',attachments:[],observedFileMarkup:true});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});
  const card=environment({attachments:[{name,status:'failed'}],observedFileMarkup:true}).attachmentNodes[0];
  e.attachmentNodes.push(card);
  const controls=card.querySelectorAll('button, [role="button"]');
  assert.equal(controls[0].getAttribute('aria-label'),name);
  assert.equal(controls[1].getAttribute('aria-label'),`Ta bort fil 1: ${name}`);
  const result=e.adapter.removeFailedSuperUploadFiles({token:'super',names:[`/tmp/${name}`]});
  assert.equal(result.ok,true);
  assert.equal(controls[1].removed,true);
});
function sentGalleryAliasEnvironment({originals,sentNames}={}) {
  const expected=originals||Array.from({length:10},(_,index)=>`gallery-${index+1}.png`);
  const withSuffix=(name,suffix)=>name.replace(/(?=\.[^.]+$)/,`(${suffix})`);
  const composerNames=expected.map(name=>withSuffix(name,2));
  const displayed=sentNames||expected.map(name=>withSuffix(name,3));
  const e=environment({draft:'',attachments:[],observedFileMarkup:true});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:expected});
  e.attachmentNodes.push(...environment({attachments:composerNames.map(name=>({name})),observedFileMarkup:true}).attachmentNodes);
  const composerState=e.adapter.superUploadState({token:'super'});
  assert.equal(composerState.attachmentsReady,true);

  let gallery;
  const controls=displayed.map((name,index)=>({isConnected:true,hidden:false,parentElement:null,
    getAttribute(key){
      if(key==='aria-label')return `Öppna bild ${index+1} av ${displayed.length}: ${name}`;
      if(key==='aria-haspopup')return 'dialog';
      if(key==='tabindex')return '0';
      return null;
    },
    getClientRects(){return [{}]},contains(node){return node?.parentElement===this},
    closest(){return null},matches(){return false},querySelectorAll(){return []}}));
  const images=displayed.map((name,index)=>({isConnected:true,hidden:false,parentElement:controls[index],
    getAttribute(key){return key==='alt'?name:null},getClientRects(){return [{}]},
    closest(selector){return /button|aria-haspopup|tabindex/.test(selector)?controls[index]:null},
    matches(){return false},querySelectorAll(){return []}}));
  gallery={isConnected:true,hidden:false,parentElement:null,innerText:'Bilder',
    getAttribute(key){return key==='data-testid'?'attachment-gallery':key==='aria-label'?'Bilder':null},
    getClientRects(){return [{}]},hasAttribute(key){return key==='aria-label'},
    contains(node){return controls.includes(node)||images.includes(node)},closest(){return null},matches(){return false},
    querySelectorAll(selector){return selector.includes('img')?images:selector.includes('button')?controls:[]}};
  controls.forEach(control=>{control.parentElement=gallery});
  gallery.parentElement=null;
  const userTurn={isConnected:true,hidden:false,innerText:'First batch',textContent:'First batch',
    getAttribute(key){return key==='data-testid'?'conversation-turn-live-gallery':null},
    getClientRects(){return [{}]},matches(selector){return selector.includes('conversation-turn')||selector.includes('article')},
    contains(node){return node===gallery||gallery.contains(node)},closest(){return null},
    querySelector(){return null},querySelectorAll(selector){
      // This deliberately models the live page: the broad attachment selector
      // sees one generic gallery ancestor, while the actual file evidence is on
      // ten aria-haspopup image controls nested inside it.
      if(selector.includes('[data-testid*="attachment"]'))return [gallery];
      if(selector.includes('img[alt]')||selector.includes('img[title]'))return images;
      if(selector.includes('button')||selector.includes('[aria-haspopup]')||selector.includes('[tabindex]'))return controls;
      return [];
    }};
  gallery.parentElement=userTurn;
  const userMessage={isConnected:true,innerText:'First batch',textContent:'First batch',
    closest(selector){return selector.includes('conversation-turn')||selector==='article'?userTurn:null}};
  e.userMessages.push(userMessage);
  return {e,state:e.adapter.superUploadState({token:'super'}),expected,composerNames,displayed};
}
test('Live generic image gallery verifies all ten files after ChatGPT changes composer aliases',()=>{
  const {state}=sentGalleryAliasEnvironment();
  assert.equal(state.submittedUserTurnFound,true);
  assert.equal(state.submittedAttachmentCount,10);
  assert.equal(state.submittedAttachmentMatchedCount,10);
  assert.equal(state.submittedAttachmentsMatch,true);
});
test('Live generic image gallery does not collapse child filename controls into one Bilder wrapper',()=>{
  const {state}=sentGalleryAliasEnvironment();
  assert.equal(state.submittedAttachmentCount,10);
  assert.deepEqual(Array.from(state.unconfirmedFiles),[]);
});
test('Live gallery requires every expected file and rejects an unrelated replacement',()=>{
  const originals=Array.from({length:10},(_,index)=>`required-${index+1}.png`);
  const sentNames=originals.map(name=>name.replace(/(?=\.[^.]+$)/,'(3)'));
  sentNames[9]='unrelated(3).png';
  const {state}=sentGalleryAliasEnvironment({originals,sentNames});
  assert.equal(state.submittedAttachmentMatchedCount,9);
  assert.equal(state.submittedAttachmentsMatch,false);
});
test('A website collision suffix cannot impersonate a genuine numbered original filename',()=>{
  const {state}=sentGalleryAliasEnvironment({originals:['report(1).png'],sentNames:['report(2).png']});
  assert.equal(state.submittedAttachmentMatchedCount,0);
  assert.equal(state.submittedAttachmentsMatch,false);
});
test('A generic focusable filename label with a hidden unrelated image is not sent attachment evidence',()=>{
  const name='report.png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const unrelatedImage={isConnected:true,hidden:true,getAttribute(key){return key==='alt'?'unrelated-icon.png':null}};
  const generic={isConnected:true,hidden:false,textContent:'',getClientRects(){return [{}]},
    getAttribute(key){return key==='aria-label'?name:key==='tabindex'?'0':null},
    closest(){return null},contains(node){return node===unrelatedImage},matches(){return false},
    querySelector(selector){return selector.includes('img')?unrelatedImage:null},querySelectorAll(){return []}};
  const userTurn={isConnected:true,innerText:'First batch',textContent:'First batch',
    matches(selector){return selector.includes('conversation-turn')||selector.includes('article')},contains(node){return node===generic},
    querySelector(){return null},querySelectorAll(selector){return selector.includes('[tabindex]')?[generic]:[]},closest(){return null}};
  const userMessage={isConnected:true,innerText:'First batch',textContent:'First batch',
    closest(selector){return selector.includes('conversation-turn')||selector==='article'?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files});e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});e.attachmentNodes.push(composerCard);e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.submittedAttachmentMatchedCount,0);
  assert.equal(state.submittedAttachmentsMatch,false);
});
test('Observed user-turn file button exposes the exact filename as its accessible name',()=>{
  const name='report.pdf',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name:'report(1).pdf'}],observedFileMarkup:true}).attachmentNodes[0];
  const sentCard=environment({attachments:[{name:'report(1).pdf'}],observedFileMarkup:true}).attachmentNodes[0];
  const userTurn={matches(selector){return selector.includes('article')},
    querySelectorAll(selector){return selector.includes('[role="group"][aria-label]')?[sentCard]:[]},
    closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});
  e.attachmentNodes.push(composerCard);
  e.adapter.superUploadState({token:'super'}); // bind the arriving composer alias before the send
  userTurn.querySelectorAll=selector=>selector.includes('[role="group"][aria-label]')?[sentCard]:[];
  sentCard.parentElement=userTurn;
  e.userMessages.push(userMessage);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(sentCard.querySelectorAll('button')[0].getAttribute('aria-label'),'report(1).pdf');
  assert.equal(state.submittedAttachmentsMatch,true);
});
test('Observed Swedish image preview label is accepted as sent attachment evidence',()=>{
  const name='fixture-gif.gif',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?`Öppna bild 1 av 3: ${name}`:null},closest(){return null}};
  const userTurn={matches(selector){return selector.includes('article')},querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files}); e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]}); e.attachmentNodes.push(composerCard); e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,true);
});
test('Sent gallery is read from the outer conversation turn when the role node is nested',()=>{
  const name='nested-gallery.png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButton={isConnected:true,hidden:false,
    getAttribute(key){return key==='aria-label'?`Open image 1 of 1: ${name}`:null},closest(){return null}};
  const outerTurn={isConnected:true,
    matches(selector){return selector.includes('conversation-turn')||selector.includes('article')},
    contains(node){return node===imageButton},
    querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const innerArticle={isConnected:true,matches(selector){return selector==='article'},querySelectorAll(){return []},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){
    if(selector==='[data-testid^="conversation-turn-"]')return outerTurn;
    if(selector==='article')return innerArticle;
    return null;
  }};
  e.adapter.beginSuperUpload({token:'super',types:files});e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});e.attachmentNodes.push(composerCard);e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.submittedUserTurnFound,true);
  assert.equal(state.submittedAttachmentCount,1);
  assert.equal(state.submittedAttachmentsMatch,true);
});
test('Sent gallery accepts an exact filename exposed only by a child image alt',()=>{
  const name='alt-only-image.png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const image={isConnected:true,getAttribute(key){return key==='alt'?name:null},closest(selector){return selector.includes('button')?imageButton:null}};
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?'Open image':null},contains(node){return node===image},closest(){return null}};
  const userTurn={isConnected:true,matches(selector){return selector.includes('conversation-turn')||selector.includes('article')},
    contains(node){return node===imageButton||node===image},querySelectorAll(selector){
      if(selector.includes('img[alt]'))return [image];
      return selector.includes('button')?[imageButton]:[];
    },closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector==='[data-testid^="conversation-turn-"]'?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files});e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]});e.attachmentNodes.push(composerCard);e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.submittedAttachmentMatchedCount,1);
  assert.equal(state.submittedAttachmentsMatch,true);
});
test('Sent attachment coverage retains a missing second duplicate filename',()=>{
  const name='same.png',e=environment({draft:'',observedFileMarkup:true});
  const composerCards=[1,2].map(()=>environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0]);
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?`Open image 1 of 1: ${name}`:null},closest(){return null}};
  const userTurn={isConnected:true,matches(selector){return selector.includes('conversation-turn')||selector.includes('article')},
    querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector==='[data-testid^="conversation-turn-"]'?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files});e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name,name]});e.attachmentNodes.push(...composerCards);e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.submittedAttachmentMatchedCount,1);
  assert.deepEqual(Array.from(state.unconfirmedFiles),[name]);
  assert.equal(state.submittedAttachmentsMatch,false);
});
test('Extra gallery controls for an already confirmed image do not hide the ten-file send',()=>{
  const name='fixture-png.png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButtons=[1,2].map(index=>({isConnected:true,hidden:false,
    getAttribute(key){return key==='aria-label'?`Open image ${index} of 2: ${name}`:null},closest(){return null}}));
  const userTurn={matches(selector){return selector.includes('article')},
    querySelectorAll(selector){return selector.includes('button')?imageButtons:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files}); e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]}); e.attachmentNodes.push(composerCard); e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,true);
});
test('Observed English image preview label is accepted but mismatched filename is rejected',()=>{
  const name='fixture-gif.gif',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?`Open image 1 of 3: other.gif`:null},closest(){return null}};
  const userTurn={matches(selector){return selector.includes('article')},querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files}); e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]}); e.attachmentNodes.push(composerCard); e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,false);
});
test('Observed Swedish single-image label accepts a numeric filename alias',()=>{
  const name='fixture-png.png',display='fixture-png(2).png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name:display}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?`Öppna bild: ${display}`:null},closest(){return null}};
  const userTurn={matches(selector){return selector.includes('article')},querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files}); e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]}); e.attachmentNodes.push(composerCard); e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,true);
});
test('Observed English single-image label rejects a mismatched numeric filename alias',()=>{
  const name='fixture-png.png',display='fixture-png(2).png',e=environment({draft:'',observedFileMarkup:true});
  const composerCard=environment({attachments:[{name:display}],observedFileMarkup:true}).attachmentNodes[0];
  const imageButton={isConnected:true,hidden:false,getAttribute(key){return key==='aria-label'?'Open image: other(2).png':null},closest(){return null}};
  const userTurn={matches(selector){return selector.includes('article')},querySelectorAll(selector){return selector.includes('button')?[imageButton]:[]},closest(){return null}};
  const userMessage={innerText:'First batch',closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.adapter.beginSuperUpload({token:'super',types:files}); e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:[name]}); e.attachmentNodes.push(composerCard); e.adapter.superUploadState({token:'super'});
  e.userMessages.push(userMessage);
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,false);
});
function canvasPreviewEnvironment({canvasVisible=true,title='Fixture Csv(2)',names=['fixture-csv.csv']}={}){
  const e=environment({draft:'',attachments:[],observedFileMarkup:true});
  const displayNames=names.map((name,index)=>name.replace(/\.csv$/i,`(${index+2}).csv`));
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:names});
  e.attachmentNodes.push(...environment({attachments:displayNames.map(name=>({name})),observedFileMarkup:true}).attachmentNodes);
  e.adapter.superUploadState({token:'super'});
  const controls=[1,2].map(()=>({isConnected:true,hidden:false,getClientRects(){return [{}]},getAttribute(){return 'Expand'}}));
  const grid={isConnected:true,hidden:false,getClientRects(){return []},parentElement:null,
    closest(selector){return selector==='canvas'?canvas:null}};
  const canvas={isConnected:true,hidden:false,parentElement:null,contains(node){return node===grid},
    getClientRects(){return canvasVisible?[{}]:[]},getAttribute(key){return key==='aria-label'?title:null},
    querySelectorAll(selector){return selector.includes('grid')?[grid]:selector.includes('button')?controls:[]}};
  grid.parentElement=canvas;
  const userTurn={isConnected:true,hidden:false,matches(selector){return selector.includes('article')},
    querySelectorAll(selector){return selector.includes('grid')?[grid]:selector.includes('button')?controls:[]},
    closest(){return null}};
  const userMessage={innerText:'First batch',isConnected:true,closest(selector){return selector.includes('conversation-turn')?userTurn:null}};
  e.userMessages.push(userMessage);
  return {e,grid,canvas};
}
test('Hidden semantic canvas grid with a visible canvas confirms the exact CSV alias',()=>{
  const {e}=canvasPreviewEnvironment();
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,true);
});
test('A semantic grid inside a hidden canvas is not sent-file evidence',()=>{
  const {e}=canvasPreviewEnvironment({canvasVisible:false});
  assert.equal(e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,false);
});
test('A canvas preview with the wrong or ambiguous title is not sent-file evidence',()=>{
  const wrong=canvasPreviewEnvironment({title:'Other Csv(2)'});
  assert.equal(wrong.e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,false);
  const ambiguous=canvasPreviewEnvironment({names:['fixture-csv.csv','fixture_csv.csv'],title:'Fixture Csv(2)'});
  assert.equal(ambiguous.e.adapter.superUploadState({token:'super'}).submittedAttachmentsMatch,false);
});
test('Observed numeric suffix aliases are ambiguous when two cards compete for one expected file',()=>{
  const e=environment({draft:'',attachments:[],observedFileMarkup:true});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['report.pdf']});
  e.attachmentNodes.push(...environment({attachments:[{name:'report(1).pdf'},{name:'report(7).pdf'}],observedFileMarkup:true}).attachmentNodes);
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,false);
});
test('Observed exact filename reserves the exact card before numeric suffix aliasing',()=>{
  const e=environment({draft:'',attachments:[],observedFileMarkup:true});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['report.pdf','report(1).pdf']});
  e.attachmentNodes.push(...environment({attachments:[{name:'report.pdf'},{name:'report(1).pdf'}],observedFileMarkup:true}).attachmentNodes);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.attachmentsReady,true);
});
test('Reconfiguring a second batch resets intent and binds a failed numeric-suffix alias to its expected name',()=>{
  const e=environment({draft:'',attachments:[],observedFileMarkup:true});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['first.pdf']});
  e.adapter.appendSuperUploadMessage({token:'super',text:'First batch',automatic:false});
  e.listeners.get('keydown')({isTrusted:true,isComposing:false,key:'Enter',shiftKey:false,
    altKey:false,ctrlKey:false,metaKey:false,target:e.composer});
  assert.equal(e.adapter.superUploadState({token:'super'}).userIntent,true);
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['report.pdf']});
  const card=environment({attachments:[{name:'report(1).pdf',status:'failed'}],observedFileMarkup:true}).attachmentNodes[0];
  e.attachmentNodes.push(card);
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.phase,'preparing');
  assert.equal(state.userIntent,false);
  assert.equal(state.failedFiles.length,1);
  assert.equal(state.failedFiles[0].name,'report.pdf');
});
test('Duplicate expected names are counted by multiplicity',()=>{
  const e=environment({draft:'',attachments:[]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['same.pdf','same.pdf']});
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,false);
  e.attachmentNodes.push(...environment({attachments:[{name:'same.pdf'},{name:'same.pdf'}]}).attachmentNodes);
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,true);
});
test('Ten expected files are ready only when all ten visible cards are present',()=>{
  const e=environment({draft:'',attachments:[]});
  const names=Array.from({length:10},(_,i)=>`file-${i}.pdf`);
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:names});
  e.attachmentNodes.push(...environment({attachments:names.map(name=>({name}))}).attachmentNodes);
  assert.equal(e.adapter.superUploadState({token:'super'}).attachmentsReady,true);
});
test('Hidden stop control does not make Super Upload busy',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.appendSuperUploadMessage({token:'super',text:'Next',automatic:true});
  e.setBusy(true); e.document.querySelector('[data-testid="stop-button"]').hidden=true;
  assert.equal(e.adapter.superUploadState({token:'super'}).busy,false);
});
test('Per-file alert is excluded from fatal alertText',()=>{
  const e=environment({draft:'',attachments:[{name:'bad.pdf',status:'failed'}]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['bad.pdf']});
  const state=e.adapter.superUploadState({token:'super'});
  assert.equal(state.alertText,''); assert.equal(state.failedFiles[0].name,'bad.pdf');
});
test('Unrelated informational alert does not cancel upload state',()=>{
  const e=environment({draft:'',attachments:[{name:'ok.pdf'}]});
  e.alerts.push({innerText:'Copied to clipboard',isConnected:true,getAttribute(){return null},closest(){return null}});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['ok.pdf']});
  assert.equal(e.adapter.superUploadState({token:'super'}).alertText,'');
});
test('Failed-card removal requires a unique known card and updates expected files',()=>{
  const e=environment({draft:'',attachments:[{name:'bad.pdf',status:'failed'},{name:'ok.png'}]});
  e.adapter.beginSuperUpload({token:'super',types:files});
  e.adapter.configureSuperUploadBatch({token:'super',expectedFiles:['bad.pdf','ok.png']});
  const result=e.adapter.removeFailedSuperUploadFiles({token:'super',names:['/x/bad.pdf']});
  assert.equal(result.ok,true); assert.deepEqual(result.expectedFiles,['ok.png']);
  assert.equal(e.attachmentNodes[0].querySelectorAll('button')[0].removed,true);
});
test('No-op automatic submit is refused without the prepared exact draft',()=>{
  const e=environment({draft:''}); e.adapter.beginSuperUpload({token:'super',types:files});
  assert.equal(e.adapter.submitSuperUpload({token:'super',expectedDraft:''}).ok,false); assert.equal(e.submitted,0);
});
