import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const source=fs.readFileSync(new URL('../../Sources/ChatDeskMac/Resources/Adapter.js',import.meta.url),'utf8');
function environment({host='chatgpt.com',inputs=[{}],focused=true,selectionText=''}={}) {
  const listeners=new Map(),calls=[];
  const copiedTypes=new Map(),ranges=[];
  const selection={get rangeCount(){return ranges.length},getRangeAt(index){return ranges[index]},
    removeAllRanges(){ranges.length=0},addRange(range){ranges.push(range)},
    toString(){return ranges.length?String(ranges[0].text||''):selectionText}};
  const location={protocol:'https:',hostname:host,href:`https://${host}/c/one`,pathname:'/c/one',search:''};
  const fileInputs=inputs.map(properties=>({disabled:false,multiple:true,isConnected:true,accept:'',
    getAttribute(name){return this[name]??null},closest(){return this},click(){calls.push('click');listeners.get('click')?.({target:this,isTrusted:false});},...properties}));
  const form={querySelectorAll(){return fileInputs}};
  const composer={value:'keep',isConnected:true,contains(e){return e===this},closest(){return form},focus(){document.activeElement=this}};
  const document={activeElement:focused?composer:{},head:{append(){}},
    querySelector(selector){return selector.includes('#prompt-textarea')?composer:null},
    querySelectorAll(){return fileInputs},addEventListener(type,f){listeners.set(type,f)},removeEventListener(type){listeners.delete(type)},
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
  return {adapter:context.ChatDeskAdapter,location,inputs:fileInputs,composer,document,listeners,calls,messages,copiedTypes};
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
