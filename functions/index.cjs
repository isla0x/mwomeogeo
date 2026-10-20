'use strict';
const {randomBytes,randomUUID}=require('node:crypto');
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,FieldValue,Timestamp}=require('firebase-admin/firestore');
const {getStorage}=require('firebase-admin/storage');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {setGlobalOptions}=require('firebase-functions/v2');
const logger=require('firebase-functions/logger');
const validate=require('./validation.cjs');
initializeApp();
setGlobalOptions({region:'asia-northeast3',maxInstances:3});
const db=getFirestore();
function identity(request) {
  if(!request.auth?.uid)throw new HttpsError('unauthenticated','앱을 다시 열고 시도해 주세요.');
  return request.auth.uid;
}
function input(read) {
  try{return read();}catch(error){throw new HttpsError('invalid-argument',error.message);}
}
exports.createDiningTable=onCall(async request=>{
  const uid=identity(request);
  const name=input(()=>validate.tableName(request.data?.name));
  for(let attempt=0;attempt<3;attempt++) {
    const tableId=randomUUID();
    const code=randomBytes(6).toString('hex').toUpperCase();
    const ref=db.collection('tables').doc(tableId);
    const invite=db.collection('_invites').doc(code);
    const created=await db.runTransaction(async tx=>{
      if((await tx.get(invite)).exists)return false;
      tx.create(ref,{name,ownerId:uid,memberIds:[uid],inviteCode:code,createdAt:FieldValue.serverTimestamp()});
      tx.create(invite,{tableId,createdAt:FieldValue.serverTimestamp()});
      return true;
    });
    if(created)return {tableId};
  }
  throw new HttpsError('aborted','식탁을 만들지 못했어요. 다시 시도해 주세요.');
});
exports.joinDiningTable=onCall(async request=>{
  const uid=identity(request);
  const code=input(()=>validate.inviteCode(request.data?.code));
  await db.runTransaction(async tx=>{
    const ref=db.collection('_joinAttempts').doc(uid);
    const state=(await tx.get(ref)).data();
    const now=Timestamp.now();
    const recent=state&&now.toMillis()-state.startedAt.toMillis()<600000;
    if(recent&&state.count>=30)throw new HttpsError('resource-exhausted','잠시 후 다시 시도해 주세요.');
    tx.set(ref,{startedAt:recent?state.startedAt:now,count:recent?state.count+1:1});
  });
  return db.runTransaction(async tx=>{
    const invite=await tx.get(db.collection('_invites').doc(code));
    if(!invite.exists)throw new HttpsError('invalid-argument','초대 코드를 다시 확인해 주세요.');
    const tableId=invite.data().tableId;
    const ref=db.collection('tables').doc(tableId);
    const table=await tx.get(ref);
    if(!table.exists)throw new HttpsError('invalid-argument','이 식탁은 더 이상 사용할 수 없어요.');
    const members=table.data().memberIds;
    if(members.includes(uid))return {tableId};
    if(members.length>=20)throw new HttpsError('resource-exhausted','한 식탁에는 최대 20명까지 함께할 수 있어요.');
    tx.update(ref,{memberIds:FieldValue.arrayUnion(uid)});
    return {tableId};
  });
});
exports.deleteMealPost=onCall(async request=>{
  const uid=identity(request);
  const tableId=input(()=>validate.documentId(request.data?.tableId));
  const postId=input(()=>validate.documentId(request.data?.postId));
  const tableRef=db.collection('tables').doc(tableId);
  const ref=tableRef.collection('posts').doc(postId);
  const photoPath=await db.runTransaction(async tx=>{
    const table=await tx.get(tableRef);
    const post=await tx.get(ref);
    if(!table.exists||!table.data().memberIds.includes(uid))throw new HttpsError('permission-denied','이 식탁에 참여하고 있지 않아요.');
    if(!post.exists)return null;
    if(post.data().authorId!==uid)throw new HttpsError('permission-denied','내 기록만 삭제할 수 있어요.');
    tx.update(ref,{deleting:true});
    return post.data().photoPath;
  });
  if(!photoPath)return {deleted:true};
  try{await db.recursiveDelete(ref);}
  catch(error){if((await ref.get()).exists)await ref.update({deleting:false});throw error;}
  // Once the post is gone, its private photo is unreadable even if cleanup fails.
  if(validate.ownsPhotoPath(photoPath,tableId,postId)) {
    try{await getStorage().bucket().file(photoPath).delete({ignoreNotFound:true});}
    catch(error){logger.error('meal_photo_cleanup_failed',{tableId,postId,code:error.code});}
  }
  return {deleted:true};
});
