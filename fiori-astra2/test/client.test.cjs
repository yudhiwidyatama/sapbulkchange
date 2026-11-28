const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
function load(name) {
  let value;
  const code = fs.readFileSync(path.join(__dirname,'../webapp/model',name+'.js'),'utf8');
  Function('sap',code)({ui:{define:(_,factory)=>{value=factory();}}});
  return value;
}
const {RunClient,validFile,canApply}=load('RunClient');
const id='11111111-2222-3333-4444-555555555555';
test('raw 20 MiB boundary, empty and extension checks',()=>{
  const file={name:'rows.XLSX',size:20971520};assert(validFile(file));
  assert(!validFile({...file,size:file.size+1}));assert(!validFile({...file,size:0}));assert(!validFile({...file,name:'rows.xlsm'}));
});
test('upload body is raw and untrusted identity is not included',async()=>{
  const calls=[];const client=new RunClient('/fixture/',async(url,options)=>{calls.push({url,options});if(url.endsWith('$metadata'))return new Response(null,{headers:{'X-CSRF-Token':'test'}});if(url.endsWith('Runs'))return Response.json({RunId:id,'@odata.etag':'W/"1"'});return new Response(null,{status:204});});
  const file={name:'sample.xlsx',size:123};assert.equal(await client.stage('DEMO',file),id);assert.deepEqual(JSON.parse(calls[1].options.body),{CompanyCode:'DEMO'});assert.equal(calls[2].options.body,file);assert.equal(calls[2].options.headers['If-Match'],'W/"1"');assert.equal(calls[2].options.headers['X-CSRF-Token'],'test');
});
test('Apply requires a server-authorized immutable READY run; never replay an uncertain POST',async()=>{
  const ready={RunId:id,State:'READY',ApplyAllowed:true,PlannedCount:1,'@odata.etag':'W/"5"'};assert(canApply(ready));for(const bad of [{State:'VALIDATING'},{ApplyAllowed:false},{PlannedCount:0},{'@odata.etag':''}])assert(!canApply({...ready,...bad}));
  let sends=0;const client=new RunClient('/fixture/',async(url,o)=>{if(url.endsWith('$metadata'))return new Response(null,{headers:{'X-CSRF-Token':'ok'}});sends++;assert.equal(o.headers['If-Match'],'W/"5"');return new Response(null,{status:412});});await assert.rejects(client.apply(ready));assert.equal(sends,1);await assert.rejects(client.apply({...ready,ApplyAllowed:false}));assert.equal(sends,1);
});
test('generate the exact downloadable workbook for independent XLSX verification',async()=>{const blob=load('Template').workbook();fs.writeFileSync(process.env.TEST_TEMPLATE||'/tmp/astra2-template.xlsx',Buffer.from(await blob.arrayBuffer()));});
