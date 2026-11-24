const MAX=65536;
export function encodeMessage(value) {
  const body=Buffer.from(JSON.stringify(value));
  if(body.length>MAX)throw Error('message_too_large');
  const header=Buffer.alloc(4);header.writeUInt32LE(body.length);
  return Buffer.concat([header,body]);
}
export function messageDecoder(onMessage) {
  let pending=Buffer.alloc(0);
  return chunk=>{
    pending=Buffer.concat([pending,chunk]);
    while(pending.length>=4) {
      const length=pending.readUInt32LE(0);
      if(length>MAX)throw Error('message_too_large');
      if(pending.length<length+4)return;
      const value=JSON.parse(pending.subarray(4,length+4).toString());
      pending=pending.subarray(length+4);
      onMessage(value);
    }
  };
}
