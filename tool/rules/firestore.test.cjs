// Tests use an isolated demo emulator; no production accounts or records are made.
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, collection, getDoc, getDocs, query, where, writeBatch, updateDoc,
  setDoc, deleteDoc, serverTimestamp, arrayUnion, Bytes} = require('firebase/firestore');

(async () => {
  const env = await initializeTestEnvironment({projectId:'demo-mwomeogeo',
    firestore: {rules:fs.readFileSync(path.join(__dirname, '../../firestore.rules'),'utf8')}});
  try {
    const owner = env.authenticatedContext('owner').firestore();
    const guest = env.authenticatedContext('guest').firestore();
    const outsider = env.authenticatedContext('outsider').firestore();
    const nobody = env.unauthenticatedContext().firestore();
    const code = 'ABCDEF1234567890ABCDEF1234567890';
    const table = 'tables/dinner';
    const meal = table+'/posts/meal';
    const photo = table+'/photos/meal';
    let checks = 0;
    const pass = async p => {await assertSucceeds(p); checks++;};
    const fail = async p => {await assertFails(p); checks++;};
    const tableData = {name:'우리 식탁', ownerId:'owner', memberIds:['owner'], inviteCode:code,
      createdAt:serverTimestamp(), updatedAt:serverTimestamp()};
    await fail(setDoc(doc(owner,table),tableData)); // must create invitation atomically
    let batch = writeBatch(owner);
    batch.set(doc(owner,table),tableData);
    batch.set(doc(owner,'_invites/'+code),{tableId:'dinner',ownerId:'owner'});
    await pass(batch.commit());
    await fail(getDoc(doc(nobody,'_invites/'+code)));
    await fail(getDocs(collection(guest,'_invites')));
    await fail(getDoc(doc(guest,table)));
    await fail(getDocs(collection(guest,'tables')));
    await pass(getDocs(query(collection(owner,'tables'),where('memberIds','array-contains','owner'))));
    await pass(getDoc(doc(guest,'_invites/'+code)));
    const join = (db,uid,c=code) => updateDoc(doc(db,table),{memberIds:arrayUnion(uid),joinCode:c,updatedAt:serverTimestamp()});
    await fail(join(guest,'guest','0'.repeat(32)));
    await fail(join(guest,'outsider'));
    await pass(join(guest,'guest'));
    await pass(join(guest,'guest')); // idempotent rejoin
    await pass(getDoc(doc(guest,table)));
    await fail(updateDoc(doc(guest,table),{ownerId:'guest'}));
    await fail(updateDoc(doc(guest,table),{memberIds:['guest'],joinCode:code,updatedAt:serverTimestamp()}));
    const postData = {authorId:'owner', authorName:'나',photoPath:photo, meal:1,caption:'점심',
      createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
    const photoData = {authorId:'owner',data:Bytes.fromUint8Array(new Uint8Array([255,216,255,217]))};
    await fail(setDoc(doc(owner,meal),postData));
    await fail(setDoc(doc(owner,photo),photoData));
    batch = writeBatch(owner);
    batch.set(doc(owner,meal),postData);batch.set(doc(owner,photo),photoData);
    await pass(batch.commit());
    await pass(getDoc(doc(guest,photo)));
    await fail(getDoc(doc(outsider,photo)));
    await fail(getDoc(doc(nobody,meal)));
    await fail(getDoc(doc(outsider,meal)));
    await fail(getDocs(collection(guest,table+'/photos')));
    await fail(updateDoc(doc(owner,photo),photoData));
    batch = writeBatch(owner);
    batch.set(doc(owner,table+'/posts/big'),{...postData,photoPath:table+'/photos/big'});
    batch.set(doc(owner,table+'/photos/big'),{...photoData,data:Bytes.fromUint8Array(new Uint8Array(131073))});
    await fail(batch.commit());
    await fail(setDoc(doc(guest,meal+'/comments/forged'),{authorId:'owner',authorName:'나',body:'위조',createdAt:serverTimestamp()}));
    await pass(setDoc(doc(guest,meal+'/comments/one'),{authorId:'guest',authorName:'친구',body:'맛있겠다',createdAt:serverTimestamp()}));
    await fail(setDoc(doc(guest,meal+'/reactions/owner_heart'),{userId:'owner',kind:'heart'}));
    await pass(setDoc(doc(guest,meal+'/reactions/guest_heart'),{userId:'guest',kind:'heart'}));
    await fail(deleteDoc(doc(guest,meal)));
    await fail(deleteDoc(doc(guest,photo)));
    await fail(updateDoc(doc(guest,meal),{deleting:true,updatedAt:serverTimestamp()}));
    await pass(updateDoc(doc(owner,meal),{deleting:true,updatedAt:serverTimestamp()}));
    await fail(setDoc(doc(guest,meal+'/comments/two'),{authorId:'guest',authorName:'친구',body:'늦은 댓글',createdAt:serverTimestamp()}));
    await pass(getDocs(collection(owner,meal+'/comments')));
    await pass(deleteDoc(doc(owner,meal+'/comments/one')));
    await pass(deleteDoc(doc(owner,meal+'/reactions/guest_heart')));
    await fail(deleteDoc(doc(owner,meal))); // photo must go in same batch (or first)
    batch = writeBatch(owner);batch.delete(doc(owner,photo));batch.delete(doc(owner,meal));
    await pass(batch.commit());
    const removed = await getDoc(doc(owner,photo));
    if (removed.exists()) throw Error('Photo leaked after deletion');
    // Fill the room through verified joins; the 21st member is rejected.
    for (let i=2;i<20;i++) {
      const db=env.authenticatedContext('member'+i).firestore();
      await pass(join(db,'member'+i));
    }
    await fail(join(outsider,'outsider'));
    console.log(`PASS: ${checks} Firestore security and sharing checks`);
  } finally {await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
