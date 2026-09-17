import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const source=fs.readFileSync(new URL('../../Sources/ChatDeskMac/Resources/Adapter.js',import.meta.url),'utf8');
function environment({host='chatgpt.com',inputs=[{}],focused=true,selectionText='',draft='keep',
                      documentLanguage='en',autoReply=true,attachments=[],observedFileMarkup=false}={}) {
  const listeners=new Map(),calls=[],userMessages=[],assistantMessages=[],alerts=[];
  const copiedTypes=new Map(),ranges=[];
  let uploading=false,busy=false,submitted=0,form;
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
  const uploadMarker={isConnected:true};
  const stopButton={isConnected:true};
  form={
    matches(selector){return uploading&&selector.includes('[data-state="uploading"]')},
    querySelector(selector){
      if(selector==='button[data-testid="send-button"]')return sendButton;
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
test('An automatic Super Upload batch refuses to overwrite a nonempty composer',()=>{
  const e=environment();e.adapter.beginSuperUpload({token:'super',types:files});
  assert.equal(e.adapter.appendSuperUploadMessage({token:'super',text:'Next batch',automatic:true}).ok,false);
  assert.equal(e.composer.value,'keep');
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
