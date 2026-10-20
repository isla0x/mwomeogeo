'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
function harness() {
  const docs=new Map();
  const deletedPhotos=[];
  const ref=p=>({path:p,collection:n=>collection(p+'/'+n)});
  const collection=p=>({doc:id=>ref(p+'/'+id)});
  const snapshot=r=>({exists:docs.has(r.path),data:()=>docs.get(r.path)});
  const transaction={
    get:async r=>snapshot(r),
    create:(r,d)=>{assert.equal(docs.has(r.path),false);docs.set(r.path,d);},
    set:(r,d)=>docs.set(r.path,d),
    update:(r,update)=>{
      const data={...docs.get(r.path)};
      for(const [key,value] of Object.entries(update))data[key]=value&&value.union?[...new Set([...(data[key]||[]),value.union])]:value;
      docs.set(r.path,data);
    }
  };
  const db={
    collection,
    runTransaction:async action=>action(transaction),
    recursiveDelete:async r=>{for(const key of docs.keys())if(key===r.path||key.startsWith(r.path+'/'))docs.delete(key);}
  };
  class HttpsError extends Error {constructor(code,message){super(message);this.code=code;}}
  const modules={
    'firebase-admin/app':{initializeApp(){}},
    'firebase-admin/firestore':{
      getFirestore:()=>db,
      FieldValue:{serverTimestamp:()=>new Date(),arrayUnion:value=>({union:value})},
      Timestamp:{now:()=>({toMillis:()=>Date.now()})}
    },
    'firebase-admin/storage':{getStorage:()=>({bucket:()=>({file:p=>({delete:async()=>deletedPhotos.push(p)})})})},
    'firebase-functions/v2/https':{onCall:handler=>handler,HttpsError},
    'firebase-functions/v2':{setGlobalOptions(){}},
    'firebase-functions/logger':{error(){}}
  };
  const module={exports:{}};
  const scopedRequire=name=>modules[name]||(name==='./validation.cjs'?require('./validation.cjs'):require(name));
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'index.cjs'),'utf8'),{require:scopedRequire,module,exports:module.exports},{filename:'index.cjs'});
  return {handlers:module.exports,docs,deletedPhotos};
}
async function runTests() {
  const passed=[];
  {
    const h=harness();
    await assert.rejects(h.handlers.createDiningTable({data:{name:'우리 둘'}}),e=>e.code==='unauthenticated');
    assert.equal(h.docs.size,0);passed.push('unauthenticated creation rejected');
  }
  {
    const h=harness();
    const {tableId}=await h.handlers.createDiningTable({auth:{uid:'alice'},data:{name:'우리 둘'}});
    const table=h.docs.get('tables/'+tableId);
    assert.deepEqual(Array.from(table.memberIds),['alice']);
    await h.handlers.joinDiningTable({auth:{uid:'bob'},data:{code:table.inviteCode.toLowerCase()}});
    await h.handlers.joinDiningTable({auth:{uid:'bob'},data:{code:table.inviteCode}});
    assert.deepEqual(Array.from(h.docs.get('tables/'+tableId).memberIds),['alice','bob']);
    passed.push('valid invite grants membership once');
    const before=Array.from(h.docs.get('tables/'+tableId).memberIds);
    await assert.rejects(h.handlers.joinDiningTable({auth:{uid:'mallory'},data:{code:'000000000000'}}),e=>e.code==='invalid-argument');
    assert.deepEqual(Array.from(h.docs.get('tables/'+tableId).memberIds),before);
    passed.push('unknown invite cannot grant membership');
  }
  {
    const h=harness();
    const {tableId}=await h.handlers.createDiningTable({auth:{uid:'alice'},data:{name:'우리 둘'}});
    const table=h.docs.get('tables/'+tableId);
    table.memberIds=Array.from({length:20},(_,i)=>'member'+i);
    await assert.rejects(h.handlers.joinDiningTable({auth:{uid:'extra'},data:{code:table.inviteCode}}),e=>e.code==='resource-exhausted');
    assert.equal(table.memberIds.length,20);passed.push('table member limit enforced');
  }
  {
    const h=harness();
    const {tableId}=await h.handlers.createDiningTable({auth:{uid:'alice'},data:{name:'우리 둘'}});
    const table=h.docs.get('tables/'+tableId);
    const postPath='tables/'+tableId+'/posts/post-1';
    const photo='tables/'+tableId+'/photos/post-1/image.jpg';
    h.docs.set(postPath,{authorId:'alice',photoPath:photo});
    h.docs.set(postPath+'/comments/comment-1',{body:'맛있겠다'});
    await assert.rejects(h.handlers.deleteMealPost({auth:{uid:'mallory'},data:{tableId,postId:'post-1'}}),e=>e.code==='permission-denied');
    table.memberIds.push('bob');
    await assert.rejects(h.handlers.deleteMealPost({auth:{uid:'bob'},data:{tableId,postId:'post-1'}}),e=>e.code==='permission-denied');
    assert.equal(h.docs.has(postPath),true);assert.equal(h.deletedPhotos.length,0);
    passed.push('outsiders and other members cannot delete author records');
    await h.handlers.deleteMealPost({auth:{uid:'alice'},data:{tableId,postId:'post-1'}});
    assert.equal(h.docs.has(postPath),false);assert.equal(h.docs.has(postPath+'/comments/comment-1'),false);
    assert.deepEqual(h.deletedPhotos,[photo]);passed.push('author deletion removes post children and exact photo');
  }
  {
    const h=harness();
    await assert.rejects(h.handlers.deleteMealPost({auth:{uid:'alice'},data:{tableId:'a/b',postId:'x'}}),e=>e.code==='invalid-argument');
    passed.push('path traversal rejected');
    const {tableId}=await h.handlers.createDiningTable({auth:{uid:'alice'},data:{name:'우리 둘'}});
    h.docs.set('tables/'+tableId+'/posts/post-1',{authorId:'alice',photoPath:'tables/another/photos/private/image.jpg'});
    await h.handlers.deleteMealPost({auth:{uid:'alice'},data:{tableId,postId:'post-1'}});
    assert.equal(h.deletedPhotos.length,0);passed.push('cleanup cannot delete an unrelated photo');
  }
  return passed;
}
module.exports={runTests};
if(require.main===module)runTests().then(passed=>console.log(JSON.stringify({status:'passed',checks:passed}))).catch(error=>{console.error(error);process.exitCode=1;});
