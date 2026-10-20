'use strict';
function tableName(value) {
  if(typeof value!=='string'||value.trim().length<1||value.trim().length>20)throw new Error('식탁 이름은 1~20자로 적어 주세요.');
  return value.trim();
}
function inviteCode(value) {
  if(typeof value!=='string'||!/^[0-9A-F]{12}$/.test(value.trim().toUpperCase()))throw new Error('12자리 초대 코드를 확인해 주세요.');
  return value.trim().toUpperCase();
}
function documentId(value) {
  if(typeof value!=='string'||!/^[a-zA-Z0-9_-]{1,128}$/.test(value))throw new Error('식탁 또는 기록을 확인해 주세요.');
  return value;
}
function ownsPhotoPath(path,tableId,postId) {
  return path===`tables/${tableId}/photos/${postId}/image.jpg`||path===`tables/${tableId}/photos/${postId}/image.png`;
}
module.exports={tableName,inviteCode,documentId,ownsPhotoPath};
